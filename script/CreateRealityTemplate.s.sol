// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";

interface IRealityV3 {
    function createTemplate(string memory content) external returns (uint256);
}

contract CreateRealityTemplate is Script {
    function run() external {
        // Retrieve the deployed Reality contract address from an environment variable
        address realityAddress = vm.envAddress("REALITY_V3_ADDRESS");
        IRealityV3 reality = IRealityV3(realityAddress);

        // Retrieve the template content from an environment variable
        string memory content = vm.envString("TEMPLATE_CONTENT");

        vm.startBroadcast();

        // Call the createTemplate function with the custom content
        uint256 templateId = reality.createTemplate(content);

        vm.stopBroadcast();

        console.log("Created template with ID:", templateId);
    }
}
