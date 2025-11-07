// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./lib/V4AddLiq.s.sol";

// Adds Uniswap v4 liquidity for 2-pool system (outcome<>long and outcome<>short pools)
// Uses OUTCOME_TOKEN_POOLS env var with format [[wrappedOutcomeToken, shortToken, longToken], ...]
// Uses MARKET_CONFIG_FILE JSON built by deploy-all.sh (v4-config.json) with fields required by V4AddLiq
contract AddLiquidityEverywhereV4 is Script, V4AddLiq {
    function run() external {
        string memory path = _getConfigFilePath();
        string memory json = vm.readFile(path);
        Cfg memory cfg = _parseV4Cfg(json);
        uint256 deposit = _parseDepositAmount(json);
        require(deposit > 0 && deposit <= type(uint128).max, "bad deposit");

        // Parse triples from env (JSON array of [outcomeToken, shortToken, longToken] addresses)
        string memory poolsJson = vm.envString("OUTCOME_TOKEN_POOLS");
        address[][] memory pools = abi.decode(vm.parseJson(poolsJson), (address[][]));

        address recipient = vm.envAddress("MY_ADDRESS");

        vm.startBroadcast();

        for (uint256 i = 0; i < pools.length; i++) {
            require(pools[i].length == 3, "pool entry must have 3 addresses");
            address outcomeTok = pools[i][0];
            address shortTok = pools[i][1];
            address longTok = pools[i][2];
            require(
                outcomeTok != address(0) && shortTok != address(0) && longTok != address(0),
                "zero address in pool"
            );
            require(
                outcomeTok != shortTok && outcomeTok != longTok && shortTok != longTok,
                "duplicate addresses in pool"
            );

            // Approvals via Permit2 then mint liquidity to both pools using V4 periphery
            _approvePermit2(cfg, outcomeTok, shortTok, longTok, deposit, uint48(block.timestamp + 30 days));
            _mintForPair(cfg, outcomeTok, shortTok, longTok, deposit, recipient, block.timestamp + 600);

            console.log("liquidity added for CSM:");
            console.logAddress(outcomeTok);
            console.logAddress(shortTok);
            console.logAddress(longTok);
        }

        vm.stopBroadcast();
    }
}
