// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

abstract contract V4CreatePool is Script {
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q192 = 1 << 192;

    struct Cfg {
        address poolManager;
        uint24 fee;
        int24 tickSpacing;
        address hook;
        uint256 initP1e18; // probability of LONG token (0 to 1e18)
    }

    function _getConfigFilePath() internal view returns (string memory) {
        return vm.envString("MARKET_CONFIG_FILE");
    }

    function _parseV4Cfg(string memory json) internal pure returns (Cfg memory cfg) {
        cfg.poolManager = vm.parseJsonAddress(json, ".poolManager");
        uint256 fee = vm.parseJsonUint(json, ".v4Fee");
        require(fee <= type(uint24).max, "v4Fee ovf");
        cfg.fee = uint24(fee);
        int256 spacing = vm.parseJsonInt(json, ".tickSpacing");
        require(spacing <= type(int24).max && spacing >= type(int24).min, "spacing oob");
        cfg.tickSpacing = int24(spacing);
        cfg.hook = vm.parseJsonAddress(json, ".hook");
        cfg.initP1e18 = vm.parseJsonUint(json, ".initP1e18");
        require(cfg.initP1e18 > 0 && cfg.initP1e18 < 1e18, "initP1e18 out of bounds");
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

    function _order(address shortToken, address longToken)
        internal
        pure
        returns (address token0, address token1, bool inverted)
    {
        if (uint160(shortToken) < uint160(longToken)) return (shortToken, longToken, false);
        return (longToken, shortToken, true);
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
}

// Check contract for 2-pool system - verifies both pools exist per CSM
contract V4CreatePoolCheck is Script, V4CreatePool {
    function run() external view {
        string memory configPath = _getConfigFilePath();
        string memory jsonContent = vm.readFile(configPath);

        Cfg memory cfg = _parseV4Cfg(jsonContent);
        require(cfg.poolManager != address(0), "poolManager unset");

        // Parse OUTCOME_TOKEN_POOLS format: [[wrappedOutcomeToken, shortToken, longToken], ...]
        string memory poolsJson = vm.envString("OUTCOME_TOKEN_POOLS");
        address[][] memory pools = abi.decode(vm.parseJson(poolsJson), (address[][]));

        IPoolManager manager = IPoolManager(cfg.poolManager);

        for (uint256 i = 0; i < pools.length; i++) {
            require(pools[i].length == 3, "pool entry must have 3 addresses");
            address outcomeToken = pools[i][0];
            address shortToken = pools[i][1];
            address longToken = pools[i][2];
            require(
                outcomeToken != address(0) && shortToken != address(0) && longToken != address(0),
                "zero token address"
            );
            require(
                outcomeToken != shortToken && outcomeToken != longToken && shortToken != longToken,
                "duplicate token addresses"
            );

            console.log("\n=== CSM #", i, "===");
            console.log("Outcome token:", outcomeToken);
            console.log("Short token:", shortToken);
            console.log("Long token:", longToken);

            // Check Pool 1: outcome <> long
            console.log("\n--- Pool 1: outcome <> long ---");
            _checkPool(manager, cfg, outcomeToken, longToken);

            // Check Pool 2: outcome <> short
            console.log("\n--- Pool 2: outcome <> short ---");
            _checkPool(manager, cfg, outcomeToken, shortToken);
        }
    }

    function _checkPool(
        IPoolManager manager,
        Cfg memory cfg,
        address tokenA,
        address tokenB
    ) internal view {
        (address token0, address token1,) = _order(tokenA, tokenB);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: cfg.fee,
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(cfg.hook)
        });
        PoolId poolId = PoolIdLibrary.toId(key);

        (uint160 sqrtPriceX96, int24 tick,, uint24 lpFee) = StateLibrary.getSlot0(manager, poolId);

        if (sqrtPriceX96 == 0) {
            console.log("Pool MISSING for token order:");
            console.logAddress(token0);
            console.logAddress(token1);
        } else {
            console.log("Pool initialized for token order:");
            console.logAddress(token0);
            console.logAddress(token1);
            console.log("sqrtPriceX96:", sqrtPriceX96);
            console.log("tick:", tick);
            console.log("lpFee bps:", lpFee);
        }
    }
}
