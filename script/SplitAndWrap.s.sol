// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";
import {String31} from "src/libs/String31.sol";
import {WrappedOutcome} from "./lib/WrappedOutcome.sol";

contract SplitAndWrap is Script {
    using String31 for string;

    struct Config {
        address collateralToken;
        uint256 amount;
        bytes32 conditionId;
        address conditionalTokens;
        address wrapped1155Factory;
        string[] outcomeNames;
    }

    function run() external virtual {
        // Read config file path from environment variable
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        // Read and parse config file
        Config memory config = parseConfig(vm.readFile(configPath));

        // Validate inputs
        require(config.collateralToken != address(0), "Invalid collateral address");
        require(config.amount > 0, "Amount must be greater than 0");
        require(config.outcomeNames.length > 0 && config.outcomeNames.length < 256, "Invalid outcome names count");
        require(config.conditionalTokens != address(0), "Invalid conditional tokens address");
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155 factory address");

        // Validate outcome name lengths
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            require(
                bytes(config.outcomeNames[i]).length <= 25,
                string.concat("Outcome name too long (max 25 chars): ", config.outcomeNames[i])
            );
        }

        // Create interfaces
        IERC20 collateral = IERC20(config.collateralToken);
        IConditionalTokens conditionalTokens = IConditionalTokens(config.conditionalTokens);
        IWrapped1155Factory wrapped1155Factory = IWrapped1155Factory(config.wrapped1155Factory);

        // Get collateral token decimals
        uint8 decimals = IERC20Metadata(config.collateralToken).decimals();

        // Generate full discrete partition (including invalid outcome)
        uint256[] memory partition = new uint256[](config.outcomeNames.length + 1);
        for (uint256 i = 0; i < config.outcomeNames.length + 1; i++) {
            partition[i] = 1 << i;
        }

        console.log("Splitting collateral tokens:");
        console.log("  Collateral:", config.collateralToken);
        console.log("  Amount:", config.amount);
        console.log("  Condition ID:", vm.toString(config.conditionId));
        console.log("  Outcome count (including invalid):", config.outcomeNames.length + 1);
        console.log("  Outcome names count:", config.outcomeNames.length);

        vm.startBroadcast();

        // Approve conditional tokens to spend collateral
        collateral.approve(config.conditionalTokens, config.amount);
        console.log("Approved ConditionalTokens to spend collateral");

        // Split position with full discrete partition
        conditionalTokens.splitPosition(
            collateral,
            bytes32(0), // parentCollectionId = 0 for top-level split
            config.conditionId,
            partition,
            config.amount
        );
        console.log("Split position completed");

        // Approve wrapped1155Factory to transfer the position tokens
        conditionalTokens.setApprovalForAll(config.wrapped1155Factory, true);
        console.log("Approved Wrapped1155Factory for all tokens");

        // Wrap each resulting position token (excluding invalid outcome)
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            _wrapOutcome(i, config, conditionalTokens, wrapped1155Factory, collateral, partition, decimals);
        }

        vm.stopBroadcast();

        console.log("\nSplit and wrap completed successfully!");
        console.log("Wrapped tokens are now in the caller's wallet.");
        console.log("Note: Invalid outcome was not wrapped as it's typically handled separately.");
    }

    function _wrapOutcome(
        uint256 i,
        Config memory config,
        IConditionalTokens conditionalTokens,
        IWrapped1155Factory wrapped1155Factory,
        IERC20 collateral,
        uint256[] memory partition,
        uint8 decimals
    ) internal {
        // Calculate position ID for this outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(
            bytes32(0), // parentCollectionId
            config.conditionId,
            partition[i]
        );
        uint256 positionId = conditionalTokens.getPositionId(collateral, collectionId);

        // Generate token name for logging
        string memory tokenName = string.concat("IF-", config.outcomeNames[i]);

        console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));
        console.log("    Position ID:", positionId);
        console.log("    Token name:", tokenName);

        // Wrap the position tokens using library
        // The requireWrappedOutcome function will create the wrapped token if it doesn't exist
        IERC20 wrappedToken = WrappedOutcome.requireWrappedOutcome(
            wrapped1155Factory, conditionalTokens, positionId, config.outcomeNames[i], collateral
        );

        // Generate data for safeTransferFrom
        bytes memory data = WrappedOutcome.outcomeErc20Data(config.outcomeNames[i], decimals);

        // Transfer the ERC1155 tokens to the factory to get wrapped tokens
        conditionalTokens.safeTransferFrom(
            vm.envOr("USER", tx.origin), config.wrapped1155Factory, positionId, config.amount, data
        );

        console.log("    Wrapped token address:", address(wrappedToken));
        console.log("    Wrapped token balance:", wrappedToken.balanceOf(tx.origin));
    }

    function parseConfig(string memory json) internal pure virtual returns (Config memory) {
        Config memory config;

        // Parse each field individually
        config.collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));
        config.amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        config.conditionId = abi.decode(vm.parseJson(json, ".conditionId"), (bytes32));
        config.conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));
        config.wrapped1155Factory = abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address));
        config.outcomeNames = abi.decode(vm.parseJson(json, ".outcomeNames"), (string[]));

        return config;
    }
}

contract SplitAndWrapCheck is SplitAndWrap {
    using String31 for string;

    function run() external override {
        // Read config file
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        Config memory config = parseConfig(vm.readFile(configPath));

        IConditionalTokens conditionalTokens = IConditionalTokens(config.conditionalTokens);
        IWrapped1155Factory wrapped1155Factory = IWrapped1155Factory(config.wrapped1155Factory);
        IERC20 collateral = IERC20(config.collateralToken);

        console.log("Checking split and wrap status for user:", vm.envOr("USER", tx.origin));
        console.log("========================================");

        // Check collateral balance and allowance
        uint256 collateralBalance = collateral.balanceOf(vm.envOr("USER", tx.origin));
        uint256 collateralAllowance = collateral.allowance(vm.envOr("USER", tx.origin), config.conditionalTokens);
        console.log("Collateral balance:", collateralBalance);
        console.log("Collateral allowance:", collateralAllowance);
        console.log(
            collateralAllowance >= config.amount ? unicode"✅ Sufficient allowance" : unicode"❌ Insufficient allowance"
        );

        // Check each outcome
        uint256[] memory partition = new uint256[](config.outcomeNames.length);
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            partition[i] = 1 << i;
        }

        console.log("\nOutcome positions:");
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));

            bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), config.conditionId, partition[i]);
            uint256 positionId = conditionalTokens.getPositionId(collateral, collectionId);

            uint256 erc1155Balance = conditionalTokens.balanceOf(vm.envOr("USER", tx.origin), positionId);
            console.log("    ERC1155 balance:", erc1155Balance);

            // Use library to generate data for wrapped token check
            uint8 decimals = IERC20Metadata(config.collateralToken).decimals();
            bytes memory data = WrappedOutcome.outcomeErc20Data(config.outcomeNames[i], decimals);

            // Check if wrapped token exists
            try wrapped1155Factory.requireWrapped1155(conditionalTokens, positionId, data) returns (IERC20 wrappedToken)
            {
                uint256 wrappedBalance = wrappedToken.balanceOf(vm.envOr("USER", tx.origin));
                console.log("    Wrapped token:", address(wrappedToken));
                console.log("    Wrapped balance:", wrappedBalance);
                console.log(wrappedBalance > 0 ? unicode"    ✅ Has wrapped tokens" : unicode"    ⚠️  No wrapped tokens");
            } catch {
                console.log(unicode"    ⚠️  Wrapped token not created yet");
            }
        }

        // Check approval status
        bool isApproved = conditionalTokens.isApprovedForAll(vm.envOr("USER", tx.origin), config.wrapped1155Factory);
        console.log("\nWrapped1155Factory approval:", isApproved ? unicode"✅ Approved" : unicode"❌ Not approved");
    }
}
