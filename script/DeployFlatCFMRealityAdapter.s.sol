// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/src/Script.sol";
import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";

import "src/FlatCFMRealityAdapter.sol";

contract DeployFlatCFMRealityAdapter is Script {
    function run() external {
        vm.startBroadcast();

        // Replace with valid addresses and values
        IRealityETH oracle = IRealityETH(vm.envAddress("REALITY_V3"));
        address arbitrator = vm.envAddress("ARBITRATOR");
        uint32 questionTimeout = uint32(vm.envUint("QUESTION_TIMEOUT"));
        uint256 minBond = vm.envUint("MIN_BOND");

        new FlatCFMRealityAdapter(oracle, arbitrator, questionTimeout, minBond);

        vm.stopBroadcast();
    }
}
