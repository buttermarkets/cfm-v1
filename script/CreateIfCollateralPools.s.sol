// SPDX-License-Identifier: GPL-3.0-or-later
// Creates Collateral <> IF (wrapped outcome) pools for FlatCFM markets.
// Uses IF_COLLATERAL_POOLS env var (JSON array of wrapped outcome token addresses)
// and COLLATERAL_TOKEN env var for the collateral token.
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "./lib/V4CreatePool.s.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract CreateIfCollateralPools is Script, V4CreatePool {
    function run() external {
        string memory configPath = _getConfigFilePath();
        string memory jsonContent = vm.readFile(configPath);

        Cfg memory cfg = _parseV4Cfg(jsonContent);
        require(cfg.poolManager != address(0), "poolManager unset");
        require(cfg.tickSpacing > 0, "tickSpacing must be > 0");

        // Force hook to 0x00 for collateral<>IF pools (per design doc)
        cfg.hook = address(0);

        // Read initP1e18 from .ifPools.initP1e18 (price = collateral per 1 IF = 1/N)
        uint256 initP1e18 = vm.parseJsonUint(jsonContent, ".ifPools.initP1e18");
        require(initP1e18 > 0 && initP1e18 < 1e18, "ifPools.initP1e18 out of bounds");

        // Read wrapped outcome tokens from env (JSON array of addresses)
        string memory ifTokensJson = vm.envString("IF_COLLATERAL_POOLS");
        address[] memory ifTokens = abi.decode(vm.parseJson(ifTokensJson), (address[]));

        // Read collateral token from env
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        require(collateralToken != address(0), "COLLATERAL_TOKEN unset");

        vm.startBroadcast();

        for (uint256 i = 0; i < ifTokens.length; i++) {
            address ifToken = ifTokens[i];
            require(ifToken != address(0), "zero IF token");
            require(ifToken != collateralToken, "IF token == collateral");

            // Create pool: IF <> collateral with price = initP1e18 (collateral per 1 IF)
            _createPool(cfg, ifToken, collateralToken, initP1e18);
        }

        vm.stopBroadcast();
    }

    function _createPool(Cfg memory cfg, address ifToken, address collateralToken, uint256 price1e18) internal {
        (address token0, address token1,) = _order(ifToken, collateralToken);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: cfg.fee,
            tickSpacing: cfg.tickSpacing,
            hooks: IHooks(cfg.hook)
        });

        // Calculate price based on token ordering
        // price1e18 is semantic: collateral per 1 IF
        // Pool price is token1/token0
        uint256 poolPrice1e18;
        if (token0 == ifToken) {
            // Pool order is (IF, collateral), so pool price = collateral/IF = price1e18
            poolPrice1e18 = price1e18;
        } else {
            // Pool order is (collateral, IF), so pool price = IF/collateral = 1/price1e18
            poolPrice1e18 = (1e36) / price1e18;
        }

        uint160 sqrtPriceX96 = _sqrtPriceX96FromPrice1e18(token0, token1, poolPrice1e18);

        try IPoolManager(cfg.poolManager).initialize(key, sqrtPriceX96) {
            console.log("Initialized collateral<>IF pool:", token0, token1);
        } catch Error(string memory reason) {
            console.log("initialize reverted:", reason);
        }
    }
}
