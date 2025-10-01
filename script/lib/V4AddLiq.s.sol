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

abstract contract V4AddLiq is Script {
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q192 = 1 << 192;

    struct Cfg {
        address payable positionManager;
        address stateView;
        address permit2;
        uint24 fee;
        int24 tickSpacing;
        address hook;
        uint256 minQ1e18; // short per long
        uint256 maxQ1e18; // short per long
    }

    struct _MintTmp {
        address token0;
        address token1;
        uint256 minP;
        uint256 maxP;
        int24 tl;
        int24 tu;
    }

    // ===== Config parsing =====
    function _getConfigFilePath() internal view returns (string memory) {
        return vm.envString("MARKET_CONFIG_FILE");
    }

    function _parseV4Cfg(string memory json) internal pure returns (Cfg memory cfg) {
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
        cfg.minQ1e18 = vm.parseJsonUint(json, ".minQ1e18");
        cfg.maxQ1e18 = vm.parseJsonUint(json, ".maxQ1e18");
        require(cfg.minQ1e18 > 0 && cfg.maxQ1e18 > 0 && cfg.minQ1e18 < cfg.maxQ1e18, "bad band");
    }

    function _parseDepositAmount(string memory json) internal pure returns (uint256) {
        return vm.parseJsonUint(json, ".depositAmount");
    }

    function _parseSlippagePct(string memory json) internal pure returns (uint256) {
        return vm.parseJsonUint(json, ".slippagePct");
    }

    // ===== Utils =====
    function _order(address shortToken, address longToken)
        internal
        pure
        returns (address token0, address token1, bool inverted)
    {
        if (uint160(shortToken) < uint160(longToken)) return (shortToken, longToken, false);
        return (longToken, shortToken, true);
    }

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

    function _poolBandFromShortLong(uint256 minQ1e18, uint256 maxQ1e18)
        internal
        pure
        returns (uint256 minP1e18, uint256 maxP1e18)
    {
        // token0 is the lower address; token1 is the higher
        // If short < long in address order, P = 1/Q; else P = Q
        // The caller ensures (short,long) were passed to _order
        // so token0==short means invert, token0==long means pass-through
        // When token0 is short (short<long): P = long/short = 1/Q
        minP1e18 = (1e36) / maxQ1e18;
        maxP1e18 = (1e36) / minQ1e18;
    }

    function _computeL(address stateView, PoolKey memory key, int24 tl, int24 tu, uint256 deposit)
        internal
        view
        returns (uint128 L)
    {
        uint160 sa = TickMath.getSqrtPriceAtTick(tl);
        uint160 sb = TickMath.getSqrtPriceAtTick(tu);
        if (sa > sb) (sa, sb) = (sb, sa);
        (uint160 sx,,,) = IStateView(stateView).getSlot0(PoolIdLibrary.toId(key));
        console.log("sx sa sb:");
        console.logUint(sx);
        console.logUint(sa);
        console.logUint(sb);
        console.log("amount0/1 max:");
        console.logUint(deposit);
        console.logUint(deposit);
        L = LiquidityAmounts.getLiquidityForAmounts(sx, sa, sb, deposit, deposit);
        console.log("computed L:");
        console.logUint(uint256(L));
    }

    function _executeMint(
        Cfg memory cfg,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper,
        uint256 deposit,
        address recipient,
        uint256 deadline
    ) internal {
        Currency c0 = Currency.wrap(token0);
        Currency c1 = Currency.wrap(token1);
        PoolKey memory key = PoolKey(c0, c1, cfg.fee, cfg.tickSpacing, IHooks(cfg.hook));

        uint128 L = _computeL(cfg.stateView, key, tickLower, tickUpper, deposit);
        require(L > 0, "zero L");

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, uint256(L), uint128(deposit), uint128(deposit), recipient, "");
        params[1] = abi.encode(c0, c1);

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
                // add others as needed
            }
            revert(); // keep the same overall behavior
        }
    }

    // ===== High level helpers =====
    function _approvePermit2(Cfg memory cfg, address shortToken, address longToken, uint256 amount, uint48 expiration)
        internal
    {
        IERC20(shortToken).approve(cfg.permit2, amount);
        IERC20(longToken).approve(cfg.permit2, amount);
        IAllowanceTransfer(cfg.permit2).approve(shortToken, cfg.positionManager, uint160(amount), expiration);
        IAllowanceTransfer(cfg.permit2).approve(longToken, cfg.positionManager, uint160(amount), expiration);
    }

    function _mintForPair(
        Cfg memory cfg,
        address shortToken,
        address longToken,
        uint256 deposit,
        address recipient,
        uint256 deadline
    ) internal {
        _MintTmp memory L;
        (L.token0, L.token1,) = _order(shortToken, longToken);
        if (L.token0 == shortToken) {
            (L.minP, L.maxP) = _poolBandFromShortLong(cfg.minQ1e18, cfg.maxQ1e18);
        } else {
            L.minP = cfg.minQ1e18;
            L.maxP = cfg.maxQ1e18;
        }
        (L.tl, L.tu) = _computeAlignedTicks(L.token0, L.token1, L.minP, L.maxP, cfg.tickSpacing);
        console.log("ticks lower/upper:");
        console.logInt(L.tl);
        console.logInt(L.tu);

        _debugPreflight(cfg, tx.origin, L.token0, L.token1, deposit);
        _executeMint(cfg, L.token0, L.token1, L.tl, L.tu, deposit, recipient, deadline);
    }

    function _debugPreflight(Cfg memory cfg, address owner, address token0, address token1, uint256 deposit)
        internal
        view
    {
        // 1) balances
        {
            uint256 b0 = IERC20(token0).balanceOf(owner);
            uint256 b1 = IERC20(token1).balanceOf(owner);
            console.log("balances token0/token1:", b0, b1);
        }

        // 2) ERC20 -> Permit2 allowances (must be >= amounts to pull)
        {
            uint256 a0 = IERC20(token0).allowance(owner, cfg.permit2);
            uint256 a1 = IERC20(token1).allowance(owner, cfg.permit2);
            console.log("allowances to Permit2:", a0, a1);
        }

        // 3) Permit2 -> PositionManager allowances (amount, expiration)
        {
            (uint160 p0, uint48 e0,) = IAllowanceTransfer(cfg.permit2).allowance(owner, token0, cfg.positionManager);
            (uint160 p1, uint48 e1,) = IAllowanceTransfer(cfg.permit2).allowance(owner, token1, cfg.positionManager);
            console.log("permit2->posm allowances:", uint256(p0), uint256(p1));
            console.log("permit2->posm expirations:", uint256(e0), uint256(e1));
        }
    }
}
