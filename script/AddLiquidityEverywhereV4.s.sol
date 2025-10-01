// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./lib/V4AddLiq.s.sol";

// Adds Uniswap v4 liquidity for all SHORT/LONG pairs provided in env SHORT_LONG_PAIRS
// Uses MARKET_CONFIG_FILE JSON built by deploy-all.sh (v4-config.json) with fields required by V4AddLiq
contract AddLiquidityEverywhereV4 is Script, V4AddLiq {
    function run() external {
        string memory path = _getConfigFilePath();
        string memory json = vm.readFile(path);
        Cfg memory cfg = _parseV4Cfg(json);
        uint256 deposit = _parseDepositAmount(json);
        require(deposit > 0 && deposit <= type(uint128).max, "bad deposit");

        // Parse pairs from env (JSON array of [short,long] addresses)
        string memory pairsJson = vm.envString("SHORT_LONG_PAIRS");
        address[][] memory pairs = abi.decode(vm.parseJson(pairsJson), (address[][]));

        address recipient = vm.envAddress("MY_ADDRESS");

        vm.startBroadcast();

        for (uint256 i = 0; i < pairs.length; i++) {
            address shortTok = pairs[i][0];
            address longTok = pairs[i][1];
            require(shortTok != address(0) && longTok != address(0) && shortTok != longTok, "bad pair");

            // Approvals via Permit2 then mint liquidity using V4 periphery
            _approvePermit2(cfg, shortTok, longTok, deposit, uint48(block.timestamp + 30 days));
            _mintForPair(cfg, shortTok, longTok, deposit, recipient, block.timestamp + 600);

            console.log("liquidity added for:");
            console.logAddress(shortTok);
            console.logAddress(longTok);
        }

        vm.stopBroadcast();
    }
}
