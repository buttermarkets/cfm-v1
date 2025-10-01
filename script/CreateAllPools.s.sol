// SPDX-License-Identifier: GPL-3.0-or-later
// This script follows Uniswap v4 "Create Pool" quickstart:
// https://docs.uniswap.org/contracts/v4/quickstart/create-pool
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "./lib/V4CreatePool.s.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

uint256 constant Q96 = 1 << 96;
// Optional bounds for early validation:
// uint160 constant MIN_SQRT_PRICE = 4295128739 + 1;
// uint160 constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342 - 1;

// Use official v4-core types and interface; avoid shadowing

contract CreateAllPools is Script, V4CreatePool {
    // Math helpers moved to V4CreatePool

    function run() external {
        string memory configPath = _getConfigFilePath();
        string memory jsonContent = vm.readFile(configPath);

        Cfg memory cfg = _parseV4Cfg(jsonContent);
        require(cfg.poolManager != address(0), "poolManager unset");
        require(cfg.tickSpacing > 0, "tickSpacing must be > 0");

        string memory pairsJson = vm.envString("SHORT_LONG_PAIRS");
        address[][] memory shortLongPairs = abi.decode(vm.parseJson(pairsJson), (address[][]));

        vm.startBroadcast();

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            require(shortLongPairs[i].length == 2, "pair length != 2");
            require(shortLongPairs[i][0] != address(0) && shortLongPairs[i][1] != address(0), "zero token address");
            require(shortLongPairs[i][0] != shortLongPairs[i][1], "duplicate token addresses");
            (address token0, address token1,) = _order(shortLongPairs[i][0], shortLongPairs[i][1]);

            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: cfg.fee,
                tickSpacing: cfg.tickSpacing,
                hooks: IHooks(cfg.hook)
            });

            // Determine initialization price strictly from human price (1e18 scaled)
            uint160 sqrtPriceX96;
            // Map init Q (short/long) to pool P (token1/token0)
            require(cfg.initQ1e18 != 0, "initQ1e18 unset");
            uint256 p1e18 =
                _poolPriceFromShortLong(token0, token1, shortLongPairs[i][0], shortLongPairs[i][1], cfg.initQ1e18);
            sqrtPriceX96 = _sqrtPriceX96FromPrice1e18(token0, token1, p1e18);

            // initialize creates the pool if necessary, otherwise reverts if already initialized
            try IPoolManager(cfg.poolManager).initialize(key, sqrtPriceX96) {
                console.log("Initialized v4 pool for:", token0, token1);
            } catch Error(string memory reason) {
                console.log("initialize reverted (Error):", reason);
            } catch (bytes memory data) {
                if (data.length >= 4) {
                    bytes4 sel;
                    assembly {
                        sel := mload(add(data, 32))
                    }
                    console.log("initialize reverted (selector):", uint256(uint32(sel)));
                } else {
                    console.log("initialize reverted (no data)");
                }
            }
        }

        vm.stopBroadcast();
    }
}
