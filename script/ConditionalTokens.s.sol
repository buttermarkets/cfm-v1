// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "../src/ConditionalTokens.sol";

contract DeployConditionalTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ConditionalTokens conditionalTokens = new ConditionalTokens();

        console.log("ConditionalTokens deployed at:", address(conditionalTokens));

        vm.stopBroadcast();
    }
}
