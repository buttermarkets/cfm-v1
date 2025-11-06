// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";
import {String31} from "src/libs/String31.sol";
import {WrappedOutcome} from "./lib/WrappedOutcome.sol";

interface IFlatCFM {
    function conditionalTokens() external view returns (IConditionalTokens);
    function questionId() external view returns (bytes32);
    function outcomeCount() external view returns (uint256);
}

contract WrapFlatCFMOutcomes is Script {
    using String31 for string;

    struct Config {
        address cfmAddress;
        address collateralToken;
        address conditionalTokens;
        address wrapped1155Factory;
        string[] outcomeNames;
    }

    function run() external virtual {
        // Read and parse config file
        Config memory config = parseConfig(vm.readFile(vm.envString("CONFIG_PATH")));

        // Validate inputs
        require(config.cfmAddress != address(0), "Invalid CFM address");
        require(config.collateralToken != address(0), "Invalid collateral address");
        require(config.conditionalTokens != address(0), "Invalid conditional tokens address");
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155 factory address");
        require(config.outcomeNames.length > 0 && config.outcomeNames.length < 256, "Invalid outcome names count");

        // Get on-chain data and validate
        uint256 outcomeCount = IFlatCFM(config.cfmAddress).outcomeCount();
        require(
            config.outcomeNames.length == outcomeCount,
            string.concat(
                "Outcome count mismatch: config has ",
                vm.toString(config.outcomeNames.length),
                " but FlatCFM has ",
                vm.toString(outcomeCount)
            )
        );

        // Validate outcome name lengths
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            require(
                bytes(config.outcomeNames[i]).length <= 25,
                string.concat("Outcome name too long (max 25 chars): ", config.outcomeNames[i])
            );
        }

        // Calculate condition ID
        bytes32 conditionId = IConditionalTokens(config.conditionalTokens).getConditionId(
            config.cfmAddress,
            IFlatCFM(config.cfmAddress).questionId(),
            outcomeCount + 1
        );

        console.log(unicode"🔨 Wrapping FlatCFM outcomes");
        console.log("  CFM address:", config.cfmAddress);
        console.log(unicode"  📊 Outcome count:", outcomeCount);
        console.log(unicode"  🪙 Collateral:", config.collateralToken);
        console.log(unicode"  🔗 Condition ID:", vm.toString(conditionId));
        console.log("");

        vm.startBroadcast();

        // Wrap each decision outcome (excluding Invalid outcome)
        for (uint256 i = 0; i < outcomeCount; i++) {
            _wrapOutcome(i, config, conditionId);
        }

        vm.stopBroadcast();

        console.log("");
        console.log(unicode"✅ Wrapped", outcomeCount, "outcome tokens successfully!");
        console.log("Note: Invalid outcome was not wrapped (skipped by default).");
    }

    function _wrapOutcome(uint256 i, Config memory config, bytes32 conditionId) internal {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);

        // Calculate position ID for this outcome
        bytes32 collectionId = ct.getCollectionId(bytes32(0), conditionId, 1 << i);
        uint256 positionId = ct.getPositionId(IERC20(config.collateralToken), collectionId);

        console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));
        console.log("    Position ID:", positionId);
        console.log("    Token name:", string.concat("IF-", config.outcomeNames[i]));

        // Wrap the position tokens using library
        address wrappedToken = address(
            WrappedOutcome.requireWrappedOutcome(
                IWrapped1155Factory(config.wrapped1155Factory),
                ct,
                positionId,
                config.outcomeNames[i],
                IERC20(config.collateralToken)
            )
        );

        console.log(unicode"    ✅ Wrapped token:", wrappedToken);
        console.log("");
    }

    function parseConfig(string memory json) internal pure virtual returns (Config memory) {
        Config memory config;

        // Parse each field individually
        config.cfmAddress = abi.decode(vm.parseJson(json, ".cfmAddress"), (address));
        config.collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));
        config.conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));
        config.wrapped1155Factory = abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address));
        config.outcomeNames = abi.decode(vm.parseJson(json, ".outcomeNames"), (string[]));

        return config;
    }
}

contract WrapFlatCFMOutcomesCheck is WrapFlatCFMOutcomes {
    function run() external override {
        Config memory config = parseConfig(vm.readFile(vm.envString("CONFIG_PATH")));

        uint256 outcomeCount = IFlatCFM(config.cfmAddress).outcomeCount();
        bytes32 conditionId = IConditionalTokens(config.conditionalTokens).getConditionId(
            config.cfmAddress,
            IFlatCFM(config.cfmAddress).questionId(),
            outcomeCount + 1
        );

        console.log("Checking wrapped token status for FlatCFM:", config.cfmAddress);
        console.log("========================================");
        console.log("Outcome count:", outcomeCount);
        console.log("Condition ID:", vm.toString(conditionId));
        console.log("");

        // Check each outcome
        for (uint256 i = 0; i < outcomeCount; i++) {
            _checkOutcome(i, config, conditionId);
        }
    }

    function _checkOutcome(uint256 i, Config memory config, bytes32 conditionId) internal {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);
        bytes32 collectionId = ct.getCollectionId(bytes32(0), conditionId, 1 << i);
        uint256 positionId = ct.getPositionId(IERC20(config.collateralToken), collectionId);

        console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));
        console.log("    Position ID:", positionId);

        bytes memory data = WrappedOutcome.outcomeErc20Data(
            config.outcomeNames[i],
            IERC20Metadata(config.collateralToken).decimals()
        );

        try IWrapped1155Factory(config.wrapped1155Factory).requireWrapped1155(ct, positionId, data) returns (
            IERC20 wrappedToken
        ) {
            console.log("    Token name:", string.concat("IF-", config.outcomeNames[i]));
            console.log(unicode"    ✅ Wrapped token:", address(wrappedToken));
        } catch {
            console.log(unicode"    ⚠️  Wrapped token not created yet");
        }
        console.log("");
    }
}
