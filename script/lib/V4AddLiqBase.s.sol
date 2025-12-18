// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IStateView} from "@uniswap/v4-periphery/src/interfaces/IStateView.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title V4AddLiqBase
/// @notice Base contract with shared utilities for Uniswap v4 liquidity operations.
/// @dev Inherited by V4AddLiq (long/short pools) and V4AddLiqOutcome (outcome<>collateral pools).
///
/// PRICE SEMANTICS:
/// - P1e18 everywhere means: P1e18 = numeraire / quoted (in 1e18 fixed-point)
/// - CSM flow (V4AddLiq): numeraire = outcomeToken, quoted = longToken/shortToken
///   => P = outcome / (long|short)
/// - Outcome<>Collateral flow (V4AddLiqOutcome): numeraire = collateralToken, quoted = ifToken
///   => P = collateral / IF (the "probability-style" interpretation)
/// - When pool order is (quoted, numeraire), pool price (token1/token0) = P (no inversion)
/// - When pool order is (numeraire, quoted), pool price (token1/token0) = 1/P (invert band)
abstract contract V4AddLiqBase is Script {
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q192 = 1 << 192;
    uint256 internal constant ONE_E36 = 1e36;

    /// @notice Base configuration shared by all v4 liquidity flows
    struct BaseCfg {
        address poolManager;
        address payable positionManager;
        address stateView;
        address permit2;
        uint24 fee;
        int24 tickSpacing;
        address hook;
    }

    // ===== Config parsing =====

    function _getConfigFilePath() internal view returns (string memory) {
        return vm.envString("MARKET_CONFIG_FILE");
    }

    function _tryParseUint(string memory json, string memory key) internal pure returns (bool ok, uint256 value) {
        try vm.parseJsonUint(json, key) returns (uint256 v) {
            return (true, v);
        } catch {
            return (false, 0);
        }
    }

    function _parseBaseCfg(string memory json) internal returns (BaseCfg memory cfg) {
        cfg.poolManager = vm.parseJsonAddress(json, ".poolManager");
        cfg.positionManager = payable(vm.parseJsonAddress(json, ".positionManager"));
        cfg.stateView = vm.parseJsonAddress(json, ".stateView");
        cfg.permit2 = vm.parseJsonAddress(json, ".permit2");
        uint256 fee = vm.parseJsonUint(json, ".v4Fee");
        require(fee <= type(uint24).max, "v4Fee ovf");
        cfg.fee = uint24(fee);
        int256 spacing = vm.parseJsonInt(json, ".tickSpacing");
        require(spacing <= type(int24).max && spacing >= type(int24).min, "spacing oob");
        cfg.tickSpacing = int24(spacing);
        cfg.hook = vm.parseJsonAddress(json, ".hook");
    }

    /// @notice Parse optional price band from JSON config
    /// @param json The JSON config string
    /// @param minKey JSON key for minP1e18 (e.g., ".minP1e18" or ".ifPools.minP1e18")
    /// @param maxKey JSON key for maxP1e18 (e.g., ".maxP1e18" or ".ifPools.maxP1e18")
    /// @return minP1e18 Min price (0 if full range)
    /// @return maxP1e18 Max price (0 if full range)
    function _parseOptionalBand(string memory json, string memory minKey, string memory maxKey)
        internal
        pure
        returns (uint256 minP1e18, uint256 maxP1e18)
    {
        (bool hasMin, uint256 minVal) = _tryParseUint(json, minKey);
        (bool hasMax, uint256 maxVal) = _tryParseUint(json, maxKey);
        if (hasMin && hasMax) {
            // Both keys exist: validate both values are > 0 (revert if either is 0)
            require(minVal > 0 && minVal < 1e18, "minP out of bounds");
            require(maxVal > 0 && maxVal <= 1e18, "maxP out of bounds");
            require(minVal < maxVal, "minP must be < maxP");
            return (minVal, maxVal);
        }
        // Either key missing: treat as full range
        return (0, 0);
    }

    /// @notice Validate amount fits in Permit2 allowance (uint160)
    function _requirePermit2Amount(uint256 amount) internal pure {
        require(amount <= type(uint160).max, "amount > uint160 max (Permit2)");
    }

    /// @notice Validate amount fits in PositionManager max amounts (uint128)
    function _requirePosmMax(uint256 amount) internal pure {
        require(amount <= type(uint128).max, "amount > uint128 max (POSM)");
    }

    // ===== Token ordering =====

    /// @dev Order two tokens by address for pool key construction.
    ///      Returns (token0, token1, inverted) where inverted=true if order was swapped.
    function _order(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1, bool inverted)
    {
        if (uint160(tokenA) < uint160(tokenB)) return (tokenA, tokenB, false);
        return (tokenB, tokenA, true);
    }

    // ===== Price utilities =====

    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    function _pow10(uint256 exp) internal pure returns (uint256) {
        require(exp <= 77, "pow10 ovf");
        uint256 r = 1;
        for (uint256 i = 0; i < exp; i++) {
            r *= 10;
        }
        return r;
    }

    /// @dev Convert a 1e18 fixed-point price to sqrtPriceX96 format.
    ///      Handles decimal scaling between token0 and token1.
    function _sqrtPriceX96FromPrice1e18(address token0, address token1, uint256 price1e18)
        internal
        view
        returns (uint160)
    {
        require(price1e18 != 0, "price 0");
        uint8 d0 = IERC20Metadata(token0).decimals();
        uint8 d1 = IERC20Metadata(token1).decimals();
        int256 diff = int256(uint256(d1)) - int256(uint256(d0));

        uint256 num = price1e18;
        uint256 den = 1e18;
        if (diff >= 0) {
            uint256 f = _pow10(uint256(diff));
            require(num <= type(uint256).max / f, "scale ovf num");
            num *= f;
        } else {
            uint256 f = _pow10(_abs(diff));
            require(den <= type(uint256).max / f, "scale ovf den");
            den *= f;
        }

        uint256 sNum = Math.sqrt(num);
        uint256 sDen = Math.sqrt(den);
        require(sDen != 0, "sqrt den 0");
        uint256 sp = Math.mulDiv(sNum, Q96, sDen);
        require(sp <= type(uint160).max, "sqrt ovf");
        return uint160(sp);
    }

    // ===== Tick utilities =====

    function _floorToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 r = tick % spacing;
        int24 flo = tick - r;
        if (r < 0) flo -= spacing;
        return flo;
    }

    function _ceilToSpacing(int24 tick, int24 spacing) internal pure returns (int24) {
        int24 flo = _floorToSpacing(tick, spacing);
        return flo == tick ? tick : flo + spacing;
    }

    function _alignedTickFromPrice1e18(
        address token0,
        address token1,
        uint256 price1e18,
        int24 tickSpacing,
        bool roundUp
    ) internal view returns (int24) {
        uint160 sqrtP = _sqrtPriceX96FromPrice1e18(token0, token1, price1e18);
        int24 rawTick = TickMath.getTickAtSqrtPrice(sqrtP);
        return roundUp ? _ceilToSpacing(rawTick, tickSpacing) : _floorToSpacing(rawTick, tickSpacing);
    }

    function _computeAlignedTicks(address token0, address token1, uint256 minP, uint256 maxP, int24 spacing)
        internal
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        tickLower = _alignedTickFromPrice1e18(token0, token1, minP, spacing, false);
        tickUpper = _alignedTickFromPrice1e18(token0, token1, maxP, spacing, true);
        if (tickLower == tickUpper) tickUpper += spacing;
        require(tickLower < tickUpper, "ticks collapsed");
    }

    /// @dev Compute full-range ticks aligned to spacing
    function _computeFullRangeTicks(int24 spacing) internal pure returns (int24 tickLower, int24 tickUpper) {
        tickLower = _ceilToSpacing(TickMath.MIN_TICK, spacing);
        tickUpper = _floorToSpacing(TickMath.MAX_TICK, spacing);
        if (tickLower >= tickUpper) tickUpper = tickLower + spacing;
    }

    // ===== Price range mapping =====

    /// @notice Map a semantic price range [minP, maxP] to pool order price range
    /// @dev Semantic price is P = numeraire / quoted (see contract-level comment).
    ///      Pool price is always token1 / token0 (after address ordering).
    ///      - If pool order is (quoted, numeraire), then pool price = P (no inversion)
    ///      - If pool order is (numeraire, quoted), then pool price = 1/P (invert band)
    /// @param tokenNumeraire The numeraire token (e.g., collateralToken or outcomeToken)
    /// @param tokenQuoted The quoted token (e.g., ifToken or longToken)
    /// @param token0 Pool token0 (lower address)
    /// @param token1 Pool token1 (higher address)
    /// @param minP Semantic min price (numeraire/quoted)
    /// @param maxP Semantic max price (numeraire/quoted)
    /// @return minOut Pool min price (token1/token0)
    /// @return maxOut Pool max price (token1/token0)
    function _mapRangeToPoolOrder(
        address tokenNumeraire,
        address tokenQuoted,
        address token0,
        address token1,
        uint256 minP,
        uint256 maxP
    ) internal pure returns (uint256 minOut, uint256 maxOut) {
        require(minP > 0 && maxP > 0 && minP < maxP, "bad P");
        // If pool order = (quoted, numeraire), pool price = token1/token0 = numeraire/quoted = P
        if (token0 == tokenQuoted && token1 == tokenNumeraire) return (minP, maxP);
        // Else pool order = (numeraire, quoted), pool price = token1/token0 = quoted/numeraire = 1/P
        // Invert and swap to keep min < max
        uint256 invMin = ONE_E36 / maxP; // 1 / maxP
        uint256 invMax = ONE_E36 / minP; // 1 / minP
        return (invMin, invMax);
    }

    // ===== Liquidity computation (unified) =====

    /// @notice Compute liquidity for given tick range and max token amounts
    /// @param stateView StateView contract for reading current pool state
    /// @param key Pool key
    /// @param tl Lower tick
    /// @param tu Upper tick
    /// @param amount0Max Max amount of token0
    /// @param amount1Max Max amount of token1
    /// @return liq Liquidity to mint
    function _computeLiquidity(
        address stateView,
        PoolKey memory key,
        int24 tl,
        int24 tu,
        uint256 amount0Max,
        uint256 amount1Max
    ) internal view returns (uint128 liq) {
        uint160 sa = TickMath.getSqrtPriceAtTick(tl);
        uint160 sb = TickMath.getSqrtPriceAtTick(tu);
        if (sa > sb) (sa, sb) = (sb, sa);
        (uint160 sx,,,) = IStateView(stateView).getSlot0(PoolIdLibrary.toId(key));
        console.log("sx sa sb:");
        console.logUint(sx);
        console.logUint(sa);
        console.logUint(sb);
        console.log("amount0Max / amount1Max:");
        console.logUint(amount0Max);
        console.logUint(amount1Max);
        liq = LiquidityAmounts.getLiquidityForAmounts(sx, sa, sb, amount0Max, amount1Max);
        console.log("computed L:");
        console.logUint(uint256(liq));
    }

    /// @notice Execute mint position via PositionManager
    /// @param cfg Base configuration
    /// @param token0 Pool token0
    /// @param token1 Pool token1
    /// @param tickLower Lower tick
    /// @param tickUpper Upper tick
    /// @param amount0Max Max amount of token0
    /// @param amount1Max Max amount of token1
    /// @param recipient LP token recipient
    /// @param deadline Transaction deadline
    function _mintPosition(
        BaseCfg memory cfg,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        uint256 deadline
    ) internal {
        _requirePosmMax(amount0Max);
        _requirePosmMax(amount1Max);

        PoolKey memory key =
            PoolKey(Currency.wrap(token0), Currency.wrap(token1), cfg.fee, cfg.tickSpacing, IHooks(cfg.hook));

        uint128 liq = _computeLiquidity(cfg.stateView, key, tickLower, tickUpper, amount0Max, amount1Max);
        require(liq > 0, "zero L");

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key, tickLower, tickUpper, uint256(liq), uint128(amount0Max), uint128(amount1Max), recipient, ""
        );
        params[1] = abi.encode(Currency.wrap(token0), Currency.wrap(token1));

        console.log("calling posm.modifyLiquidities (MINT_POSITION, SETTLE_PAIR)...");
        try PositionManager(cfg.positionManager).modifyLiquidities(
            abi.encode(abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR)), params), deadline
        ) {
            console.log("posm.modifyLiquidities: OK");
        } catch (bytes memory err) {
            console.log("posm.modifyLiquidities: REVERT");
            console.logBytes(err);
            if (err.length >= 4) {
                bytes4 sel;
                assembly {
                    sel := mload(add(err, 32))
                }
                console.logBytes4(sel);
                if (sel == 0x5212cba1) console.log("=> IPoolManager.CurrencyNotSettled");
                if (sel == 0xd4d8f3e6) console.log("=> TickBitmap.TickMisaligned");
                if (sel == 0x486aa307) console.log("=> Pool/Manager PoolNotInitialized");
            }
            revert();
        }
    }

    // ===== Semantic mint primitive =====

    struct _SemanticMintTmp {
        address token0;
        address token1;
        uint256 amount0Max;
        uint256 amount1Max;
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Mint a single pool with semantic token/price ordering
    /// @dev This is the main entry point for all pool liquidity operations.
    ///      It handles token ordering, amount mapping, tick computation, and minting.
    /// @param cfg Base configuration
    /// @param tokenQuoted The quoted token (denominator in price ratio)
    /// @param tokenNumeraire The numeraire token (numerator in price ratio)
    /// @param minP1e18 Min semantic price (numeraire/quoted), 0 for full range
    /// @param maxP1e18 Max semantic price (numeraire/quoted), 0 for full range
    /// @param amountQuotedMax Max amount of quoted token
    /// @param amountNumeraireMax Max amount of numeraire token
    /// @param recipient LP token recipient
    /// @param deadline Transaction deadline
    function _mintSinglePoolSemantic(
        BaseCfg memory cfg,
        address tokenQuoted,
        address tokenNumeraire,
        uint256 minP1e18,
        uint256 maxP1e18,
        uint256 amountQuotedMax,
        uint256 amountNumeraireMax,
        address recipient,
        uint256 deadline
    ) internal {
        _SemanticMintTmp memory tmp;

        // 1. Determine pool order
        (tmp.token0, tmp.token1,) = _order(tokenQuoted, tokenNumeraire);

        // 2. Map semantic amounts to (amount0Max, amount1Max)
        if (tmp.token0 == tokenQuoted) {
            tmp.amount0Max = amountQuotedMax;
            tmp.amount1Max = amountNumeraireMax;
        } else {
            tmp.amount0Max = amountNumeraireMax;
            tmp.amount1Max = amountQuotedMax;
        }

        // 3. Determine ticks
        (tmp.tickLower, tmp.tickUpper) = _computeTicks(
            cfg.tickSpacing, tokenNumeraire, tokenQuoted, tmp.token0, tmp.token1, minP1e18, maxP1e18
        );

        // 4. Debug print
        console.log("=== _mintSinglePoolSemantic ===");
        console.log("Semantic pair (quoted, numeraire):");
        console.logAddress(tokenQuoted);
        console.logAddress(tokenNumeraire);
        console.log("Semantic price range (numeraire/quoted):", minP1e18, maxP1e18);
        console.log("Pool order (token0, token1):");
        console.logAddress(tmp.token0);
        console.logAddress(tmp.token1);
        console.log("Amount0Max / Amount1Max:", tmp.amount0Max, tmp.amount1Max);
        console.log("Ticks lower/upper:");
        console.logInt(tmp.tickLower);
        console.logInt(tmp.tickUpper);

        // 5. Preflight + mint
        _debugPreflight(cfg, tx.origin, tmp.token0, tmp.token1);
        _mintPosition(cfg, tmp.token0, tmp.token1, tmp.tickLower, tmp.tickUpper, tmp.amount0Max, tmp.amount1Max, recipient, deadline);
    }

    /// @notice Compute ticks from semantic price range
    /// @dev Extracted to reduce stack depth in _mintSinglePoolSemantic
    function _computeTicks(
        int24 tickSpacing,
        address tokenNumeraire,
        address tokenQuoted,
        address token0,
        address token1,
        uint256 minP1e18,
        uint256 maxP1e18
    ) internal view returns (int24 tickLower, int24 tickUpper) {
        if (minP1e18 == 0 && maxP1e18 == 0) {
            // Full-range
            return _computeFullRangeTicks(tickSpacing);
        }

        // Clamp and map price range
        (uint256 mappedMinP, uint256 mappedMaxP) = _clampAndMapPriceRange(
            tokenNumeraire, tokenQuoted, token0, token1, minP1e18, maxP1e18
        );
        return _computeAlignedTicks(token0, token1, mappedMinP, mappedMaxP, tickSpacing);
    }

    /// @notice Clamp boundary values and map semantic price range to pool order
    /// @dev Extracted to reduce stack depth
    function _clampAndMapPriceRange(
        address tokenNumeraire,
        address tokenQuoted,
        address token0,
        address token1,
        uint256 minP1e18,
        uint256 maxP1e18
    ) internal pure returns (uint256 mappedMinP, uint256 mappedMaxP) {
        // Clamp boundary values
        uint256 minP = minP1e18;
        uint256 maxP = maxP1e18;
        if (minP == 0 && maxP > 0) {
            minP = 1; // epsilon to avoid price==0 in tick math
        }
        if (maxP <= minP) {
            maxP = minP + 1;
        }

        // Map semantic band to pool order
        return _mapRangeToPoolOrder(tokenNumeraire, tokenQuoted, token0, token1, minP, maxP);
    }

    // ===== Permit2 approvals (2-token version) =====

    function _approvePermit2(
        BaseCfg memory cfg,
        address tokenA,
        address tokenB,
        uint256 amount,
        uint48 expiration
    ) internal {
        _requirePermit2Amount(amount);
        IERC20(tokenA).approve(cfg.permit2, amount);
        IERC20(tokenB).approve(cfg.permit2, amount);
        IAllowanceTransfer(cfg.permit2).approve(tokenA, cfg.positionManager, uint160(amount), expiration);
        IAllowanceTransfer(cfg.permit2).approve(tokenB, cfg.positionManager, uint160(amount), expiration);
    }

    // ===== Debug helpers =====

    function _debugPreflight(BaseCfg memory cfg, address owner, address token0, address token1)
        internal
        view
    {
        // 1) balances
        {
            uint256 b0 = IERC20(token0).balanceOf(owner);
            uint256 b1 = IERC20(token1).balanceOf(owner);
            console.log("balances token0/token1:", b0, b1);
        }

        // 2) ERC20 -> Permit2 allowances
        {
            uint256 a0 = IERC20(token0).allowance(owner, cfg.permit2);
            uint256 a1 = IERC20(token1).allowance(owner, cfg.permit2);
            console.log("allowances to Permit2:", a0, a1);
        }

        // 3) Permit2 -> PositionManager allowances
        {
            (uint160 p0, uint48 e0,) = IAllowanceTransfer(cfg.permit2).allowance(owner, token0, cfg.positionManager);
            (uint160 p1, uint48 e1,) = IAllowanceTransfer(cfg.permit2).allowance(owner, token1, cfg.positionManager);
            console.log("permit2->posm allowances:", uint256(p0), uint256(p1));
            console.log("permit2->posm expirations:", uint256(e0), uint256(e1));
        }
    }
}
