// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "./lib/V4AddLiqOutcome.s.sol";

/// @title AddLiquidityIfCollateralV4
/// @notice Adds Uniswap v4 liquidity to Collateral <> IF pools with asymmetric amounts.
/// @dev Uses IF_COLLATERAL_POOLS env var (JSON array of wrapped outcome token addresses)
///      and COLLATERAL_TOKEN env var for the collateral token.
///      Reads .ifPools.{ifPerPool, collateralPerPool, minP1e18, maxP1e18} from config.
contract AddLiquidityIfCollateralV4 is Script, V4AddLiqOutcome {
    function run() external {
        string memory path = _getConfigFilePath();
        string memory json = vm.readFile(path);
        OutcomeCfg memory cfg = _parseOutcomeCfg(json);

        // Force hook to 0x00 for collateral<>IF pools
        cfg.base.hook = address(0);

        // Read wrapped outcome tokens from env (JSON array of addresses)
        string memory ifTokensJson = vm.envString("IF_COLLATERAL_POOLS");
        address[] memory ifTokens = abi.decode(vm.parseJson(ifTokensJson), (address[]));

        // Read collateral token from env
        address collateralToken = vm.envAddress("COLLATERAL_TOKEN");
        require(collateralToken != address(0), "COLLATERAL_TOKEN unset");

        address recipient = vm.envAddress("MY_ADDRESS");

        vm.startBroadcast();

        for (uint256 i = 0; i < ifTokens.length; i++) {
            address ifToken = ifTokens[i];
            require(ifToken != address(0), "zero IF token");
            require(ifToken != collateralToken, "IF token == collateral");

            if (cfg.skipIfExists) {
                PoolKey memory key = _buildPoolKey(cfg.base, ifToken, collateralToken);
                PoolId poolId = PoolIdLibrary.toId(key);
                uint128 existingLiquidity = IStateView(cfg.base.stateView).getLiquidity(poolId);

                if (existingLiquidity > 0) {
                    console.log("Skipping pool (liquidity exists):", existingLiquidity);
                    console.log("IF token:", ifToken);
                    continue;
                }
            }

            console.log("=== Adding liquidity to collateral<>IF pool ===");
            console.log("IF token:", ifToken);
            console.log("Collateral:", collateralToken);
            console.log("IF amount:", cfg.ifPerPool);
            console.log("Collateral amount:", cfg.collateralPerPool);
            console.log("Price range (collateral/IF):", cfg.minP1e18, cfg.maxP1e18);

            // Approvals via Permit2
            uint256 maxAmount = cfg.ifPerPool > cfg.collateralPerPool ? cfg.ifPerPool : cfg.collateralPerPool;
            uint48 exp = uint48(block.timestamp + 2_592_000); // ~30 days
            _approvePermit2(cfg.base, ifToken, collateralToken, maxAmount, exp);

            // Mint liquidity with asymmetric amounts and price range
            _mintSinglePoolAsymmetric(cfg, ifToken, collateralToken, recipient, block.timestamp + 600);

            console.log("Liquidity added for collateral<>IF pool");
        }

        vm.stopBroadcast();
    }
}
