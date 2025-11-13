// SPDX-License-Identifier: GPL-3.0-or-later
// Add Uniswap v4 liquidity for a single token pair using min/max price band.
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./lib/V4AddLiq.s.sol";

contract AddLiquidityV4 is Script, V4AddLiq {
    function run() external {
        // Parse shared v4 cfg and deposit
        string memory path = _getConfigFilePath();
        string memory json = vm.readFile(path);
        Cfg memory cfg = _parseV4Cfg(json);
        uint256 deposit = _parseDepositAmount(json);
        require(deposit > 0 && deposit <= type(uint128).max, "bad deposit");

        // Caller provides tokens (outcomeToken, scalarToken). Env var names kept for compatibility.
        address outcomeToken = vm.envAddress("SHORT_TOKEN");
        address scalarToken = vm.envAddress("LONG_TOKEN");
        require(outcomeToken != address(0) && scalarToken != address(0) && outcomeToken != scalarToken, "bad pair");
        address recipient = vm.envAddress("MY_ADDRESS");

        vm.startBroadcast();

        // Approve via Permit2 (both raw approve and allowance to PM)
        _approvePermit2(cfg, outcomeToken, scalarToken, deposit, uint48(block.timestamp + 30 days));

        _mintForPair(cfg, outcomeToken, scalarToken, deposit, recipient, block.timestamp + 600);

        vm.stopBroadcast();

        console.log(unicode"✓ v4 liquidity added");
        console.logAddress(outcomeToken);
        console.logAddress(scalarToken);
    }
}
