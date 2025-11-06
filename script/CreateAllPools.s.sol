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
        require(cfg.initP1e18 > 0 && cfg.initP1e18 < 1e18, "initP1e18 out of bounds");

        // Read triples (outcomeToken, short, long)
        string memory triplesJson = vm.envString("OUTCOME_TOKEN_POOLS");
        address[][] memory poolTriples = abi.decode(vm.parseJson(triplesJson), (address[][]));

        vm.startBroadcast();

        for (uint256 i = 0; i < poolTriples.length; i++) {
            require(poolTriples[i].length == 3, "triple length != 3");
            address outcomeToken = poolTriples[i][0];
            address shortToken = poolTriples[i][1];
            address longToken = poolTriples[i][2];

            // Create TWO pools for each triple:
            // 1. outcomeToken <> longToken with price = initP1e18
            _createPool(cfg, outcomeToken, longToken, cfg.initP1e18);

            // 2. outcomeToken <> shortToken with price = (1e18 - initP1e18)
            _createPool(cfg, outcomeToken, shortToken, 1e18 - cfg.initP1e18);
        }

        vm.stopBroadcast();
    }

    function _createPool(Cfg memory cfg, address tokenA, address tokenB, uint256 price1e18) internal {
        require(tokenA != address(0) && tokenB != address(0), "zero token");
        require(tokenA != tokenB, "duplicate tokens");

        (address token0, address token1,) = _order(tokenA, tokenB);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: cfg.fee,
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(cfg.hook)
        });

        // Calculate price based on token ordering
        uint256 poolPrice1e18;
        if (token0 == tokenA) {
            // token1/token0 = tokenB/tokenA
            poolPrice1e18 = price1e18;
        } else {
            // token1/token0 = tokenA/tokenB = 1/price
            poolPrice1e18 = (1e36) / price1e18;
        }

        uint160 sqrtPriceX96 = _sqrtPriceX96FromPrice1e18(token0, token1, poolPrice1e18);

        try IPoolManager(cfg.poolManager).initialize(key, sqrtPriceX96) {
            console.log("Initialized pool:", token0, token1);
        } catch Error(string memory reason) {
            console.log("initialize reverted:", reason);
        }
    }
}
