// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";

contract DeployFlatCFMFactory is Script {
    function run() external {
        vm.startBroadcast();

        // Try reading environment variables.
        address conditionalTokensAddr = _requireEnvAddress("CONDITIONAL_TOKENS");
        address wrapped1155FactoryAddr = _requireEnvAddress("WRAPPED_1155_FACTORY");

        // Convert to interfaces.
        IConditionalTokens conditionalTokens = IConditionalTokens(conditionalTokensAddr);
        IWrapped1155Factory wrapped1155Factory = IWrapped1155Factory(wrapped1155FactoryAddr);

        // Deploy.
        FlatCFMFactory factory = new FlatCFMFactory(conditionalTokens, wrapped1155Factory);
        console.log("FlatCFMFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }

    // Helper that reverts if env var isn't set or is zero.
    function _requireEnvAddress(string memory key) internal view returns (address) {
        address addr;
        try vm.envAddress(key) returns (address val) {
            addr = val;
        } catch {
            revert(string.concat("Missing or invalid env variable: ", key));
        }
        require(addr != address(0), string.concat("Zero address for: ", key));
        return addr;
    }
}
