// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";
import {String31} from "src/libs/String31.sol";

contract UnwrapAndMerge is Script {
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

        console.log("Unwrapping and merging tokens:");
        console.log("  Collateral:", config.collateralToken);
        console.log("  Amount:", config.amount);
        console.log("  Condition ID:", vm.toString(config.conditionId));
        console.log("  Outcome count (including invalid):", config.outcomeNames.length + 1);
        console.log("  Outcome names count:", config.outcomeNames.length);

        vm.startBroadcast();

        // Unwrap each IF token back to ERC1155 conditional tokens
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            _unwrapOutcome(i, config, conditionalTokens, wrapped1155Factory, collateral, partition, decimals);
        }

        // Ensure user has the invalid outcome tokens as well
        bytes32 invalidCollectionId = conditionalTokens.getCollectionId(
            bytes32(0),
            config.conditionId,
            partition[config.outcomeNames.length]
        );
        uint256 invalidPositionId = conditionalTokens.getPositionId(collateral, invalidCollectionId);
        uint256 invalidBalance = conditionalTokens.balanceOf(msg.sender, invalidPositionId);
        console.log("Invalid outcome ERC1155 balance:", invalidBalance);
        require(
            invalidBalance >= config.amount,
            "Insufficient invalid outcome token balance for merge"
        );

        // Merge all conditional tokens back to collateral
        conditionalTokens.mergePositions(
            collateral,
            bytes32(0), // parentCollectionId = 0 for top-level merge
            config.conditionId,
            partition,
            config.amount
        );
        console.log("Merge positions completed");

        vm.stopBroadcast();

        console.log("\nUnwrap and merge completed successfully!");
        console.log("Collateral tokens are now back in the caller's wallet.");
    }

    function _unwrapOutcome(
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

        // Encode the data for wrapped token (same as in wrap)
        string memory tokenName = string.concat("IF-", config.outcomeNames[i]);

        console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));
        console.log("    Position ID:", positionId);
        console.log("    Token name:", tokenName);

        // Get the wrapped token address
        bytes memory data = abi.encodePacked(tokenName.toString31(), tokenName.toString31(), decimals);
        IERC20 wrappedToken = wrapped1155Factory.requireWrapped1155(conditionalTokens, positionId, data);
        
        // Check wrapped token balance
        uint256 wrappedBalance = wrappedToken.balanceOf(msg.sender);
        console.log("    Wrapped token balance:", wrappedBalance);
        
        require(wrappedBalance >= config.amount, string.concat("Insufficient wrapped token balance for ", config.outcomeNames[i]));

        // Approve wrapped1155Factory to spend wrapped tokens
        wrappedToken.approve(address(wrapped1155Factory), config.amount);
        console.log("    Approved factory to spend wrapped tokens");

        // Unwrap the ERC20 tokens back to ERC1155 conditional tokens
        wrapped1155Factory.unwrap(
            conditionalTokens,
            positionId,
            config.amount,
            msg.sender,
            data
        );
        console.log("    Unwrapped tokens back to ERC1155");

        // Verify we received the ERC1155 tokens
        uint256 erc1155Balance = conditionalTokens.balanceOf(msg.sender, positionId);
        console.log("    ERC1155 balance after unwrap:", erc1155Balance);
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

contract UnwrapAndMergeCheck is UnwrapAndMerge {
    using String31 for string;

    function run() external override {
        // Read config file
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        Config memory config = parseConfig(vm.readFile(configPath));

        IConditionalTokens conditionalTokens = IConditionalTokens(config.conditionalTokens);
        IWrapped1155Factory wrapped1155Factory = IWrapped1155Factory(config.wrapped1155Factory);
        IERC20 collateral = IERC20(config.collateralToken);

        console.log("Checking unwrap and merge status for user:", vm.envOr("USER", msg.sender));
        console.log("========================================");

        // Check collateral balance
        uint256 collateralBalance = collateral.balanceOf(vm.envOr("USER", msg.sender));
        console.log("Collateral balance:", collateralBalance);

        // Check each outcome's wrapped token balance
        uint256[] memory partition = new uint256[](config.outcomeNames.length + 1);
        for (uint256 i = 0; i < config.outcomeNames.length + 1; i++) {
            partition[i] = 1 << i;
        }

        console.log("\nWrapped token balances:");
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            console.log(string.concat("  Outcome ", vm.toString(i), " (", config.outcomeNames[i], "):"));

            bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), config.conditionId, partition[i]);
            uint256 positionId = conditionalTokens.getPositionId(collateral, collectionId);

            // Reconstruct the data to check for wrapped token
            string memory tokenName = string.concat("IF-", config.outcomeNames[i]);
            uint8 decimals = IERC20Metadata(config.collateralToken).decimals();
            bytes memory data = abi.encodePacked(tokenName.toString31(), tokenName.toString31(), decimals);

            // Check wrapped token balance
            try wrapped1155Factory.requireWrapped1155(conditionalTokens, positionId, data) returns (IERC20 wrappedToken)
            {
                uint256 wrappedBalance = wrappedToken.balanceOf(vm.envOr("USER", msg.sender));
                console.log("    Wrapped token:", address(wrappedToken));
                console.log("    Wrapped balance:", wrappedBalance);
                console.log(wrappedBalance >= config.amount ? unicode"    ✅ Sufficient for merge" : unicode"    ❌ Insufficient for merge");
            } catch {
                console.log(unicode"    ⚠️  Wrapped token not found");
            }

            // Check ERC1155 balance
            uint256 erc1155Balance = conditionalTokens.balanceOf(vm.envOr("USER", msg.sender), positionId);
            console.log("    ERC1155 balance:", erc1155Balance);
        }

        // Check invalid outcome ERC1155 balance
        bytes32 invalidCollectionId = conditionalTokens.getCollectionId(bytes32(0), config.conditionId, partition[config.outcomeNames.length]);
        uint256 invalidPositionId = conditionalTokens.getPositionId(collateral, invalidCollectionId);
        uint256 invalidBalance = conditionalTokens.balanceOf(vm.envOr("USER", msg.sender), invalidPositionId);
        console.log("\nInvalid outcome ERC1155 balance:", invalidBalance);
        
        // Check if user has complete set for merging
        bool canMerge = true;
        for (uint256 i = 0; i < config.outcomeNames.length; i++) {
            bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), config.conditionId, partition[i]);
            uint256 positionId = conditionalTokens.getPositionId(collateral, collectionId);
            uint256 balance = conditionalTokens.balanceOf(vm.envOr("USER", msg.sender), positionId);
            if (balance < config.amount) {
                canMerge = false;
                break;
            }
        }
        if (invalidBalance < config.amount) {
            canMerge = false;
        }
        
        console.log(canMerge ? unicode"\n✅ Can merge complete set back to collateral" : unicode"\n❌ Cannot merge - incomplete set");
    }
}
