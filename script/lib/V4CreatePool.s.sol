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
        uint256 initQ1e18; // short per long
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
        cfg.initQ1e18 = vm.parseJsonUint(json, ".initQ1e18");
        require(cfg.initQ1e18 > 0, "initQ1e18 bad");
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

    /// Map a single Q price (short/long) into pool P price (token1/token0)
    function _poolPriceFromShortLong(
        address token0,
        address token1,
        address shortToken,
        address longToken,
        uint256 Q1e18
    ) internal pure returns (uint256 P1e18) {
        require(Q1e18 != 0, "Q=0");
        if (token0 == shortToken && token1 == longToken) {
            // P = long/short = 1/Q
            P1e18 = (1e36) / Q1e18;
        } else if (token0 == longToken && token1 == shortToken) {
            // P = short/long = Q
            P1e18 = Q1e18;
        } else {
            revert("tokens mismatch");
        }
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

contract V4CreatePoolCheck is Script, V4CreatePool {
    function run() external view {
        string memory configPath = _getConfigFilePath();
        string memory jsonContent = vm.readFile(configPath);

        Cfg memory cfg = _parseV4Cfg(jsonContent);
        require(cfg.poolManager != address(0), "poolManager unset");

        string memory pairsJson = vm.envString("SHORT_LONG_PAIRS");
        address[][] memory shortLongPairs = abi.decode(vm.parseJson(pairsJson), (address[][]));

        IPoolManager manager = IPoolManager(cfg.poolManager);

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            require(shortLongPairs[i].length == 2, "pair length != 2");
            address shortToken = shortLongPairs[i][0];
            address longToken = shortLongPairs[i][1];
            require(shortToken != address(0) && longToken != address(0), "zero token address");
            require(shortToken != longToken, "duplicate token addresses");

            (address token0, address token1,) = _order(shortToken, longToken);

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
                console.log("Pool missing for token order:");
                console.logAddress(token0);
                console.logAddress(token1);
            } else {
                console.log("Pool initialized for token order:");
                console.logAddress(token0);
                console.logAddress(token1);
                console.log("sqrtPriceX96:");
                console.logUint(sqrtPriceX96);
                console.log("tick:");
                console.logInt(tick);
                console.log("lpFee bps:");
                console.logUint(lpFee);
            }
        }
    }
}
