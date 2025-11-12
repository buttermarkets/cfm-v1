// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";

contract UnwrapAndRedeem is Script {
    struct Config {
        address wrapped1155Factory;
        address conditionalTokens;
        address erc20; // wrapped token address
        uint256 amount;
        bytes tokenData; // prepared by bash script
        uint256 positionId; // prepared by bash script
        bytes32 conditionId;
        address collateralToken;
    }

    function run() external virtual {
        // Read config file path from environment variable
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        // Read and parse config file
        Config memory config = parseConfig(vm.readFile(configPath));

        // Validate inputs
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155Factory address");
        require(config.conditionalTokens != address(0), "Invalid conditionalTokens address");
        require(config.erc20 != address(0), "Invalid erc20 address");
        require(config.amount > 0, "Amount must be greater than 0");
        require(config.positionId != 0, "Invalid positionId");
        require(config.conditionId != bytes32(0), "Invalid conditionId");
        require(config.collateralToken != address(0), "Invalid collateralToken address");
        require(config.tokenData.length > 0, "tokenData must not be empty");

        console.log("Unwrapping and redeeming tokens:");
        console.log("  Wrapped token:", config.erc20);
        console.log("  Amount:", config.amount);
        console.log("  Position ID:", config.positionId);
        console.log("  Condition ID:", vm.toString(config.conditionId));

        // Check that condition is resolved
        uint256 payoutDenominator = IConditionalTokens(config.conditionalTokens).payoutDenominator(config.conditionId);
        require(payoutDenominator > 0, "Condition not resolved yet");
        console.log("  Payout denominator:", payoutDenominator);

        vm.startBroadcast();

        // Step 1: Unwrap ERC20 tokens back to ERC1155
        _unwrap(config);

        // Step 2: Redeem positions
        console.log("\n2. Redeeming positions...");

        // Determine outcome index and payout information
        (uint256 indexSet, uint256 payoutNumerator) = _locateIndexAndPayout(
            IConditionalTokens(config.conditionalTokens),
            IERC20(config.collateralToken),
            config.positionId,
            config.conditionId
        );
        console.log("  Index set:", indexSet);
        console.log("  Payout numerator:", payoutNumerator);
        console.log("  Expected collateral:", (config.amount * payoutNumerator) / payoutDenominator);

        // Redeem the position
        {
            IERC20 collateral = IERC20(config.collateralToken);
            uint256 collateralBefore = collateral.balanceOf(msg.sender);
            console.log("  Collateral balance before:", collateralBefore);

            uint256[] memory indexSets = new uint256[](1);
            indexSets[0] = indexSet;

            IConditionalTokens(config.conditionalTokens).redeemPositions(
                collateral,
                bytes32(0), // parentCollectionId = 0 for top-level redemption
                config.conditionId,
                indexSets
            );

            uint256 collateralAfter = collateral.balanceOf(msg.sender);
            console.log("  Collateral balance after:", collateralAfter);
            console.log("  Collateral received:", collateralAfter - collateralBefore);
        }

        vm.stopBroadcast();

        console.log(unicode"\n✅ Unwrap and redeem completed successfully!");
    }

    function _unwrap(Config memory config) internal {
        console.log("\n1. Unwrapping tokens...");
        IERC20 wrappedToken = IERC20(config.erc20);
        IWrapped1155Factory factory = IWrapped1155Factory(config.wrapped1155Factory);
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);

        uint256 wrappedBalance = wrappedToken.balanceOf(msg.sender);
        console.log("  Wrapped token balance:", wrappedBalance);
        require(wrappedBalance >= config.amount, "Insufficient wrapped token balance");

        wrappedToken.approve(address(factory), config.amount);
        console.log("  Approved factory to spend wrapped tokens");

        factory.unwrap(ct, config.positionId, config.amount, msg.sender, config.tokenData);
        console.log("  Unwrapped tokens back to ERC1155");

        console.log("  ERC1155 balance after unwrap:", ct.balanceOf(msg.sender, config.positionId));
    }

    function _getCollectionIdFromPosition(
        IConditionalTokens conditionalTokens,
        IERC20 collateral,
        uint256 positionId,
        bytes32 conditionId
    ) internal view returns (bytes32) {
        // Try to reverse-engineer the collection ID from the position ID
        // positionId = uint(keccak256(abi.encodePacked(collateral, collectionId)))
        // We need to brute-force check all possible outcomes

        for (uint256 i = 0; i < 256; i++) {
            uint256 indexSet = 1 << i;
            bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
            uint256 testPositionId = conditionalTokens.getPositionId(collateral, collectionId);

            if (testPositionId == positionId) {
                return collectionId;
            }
        }

        revert("Could not find collection ID for position");
    }

    function _locateIndexAndPayout(IConditionalTokens ct, IERC20 collateral, uint256 positionId, bytes32 conditionId)
        internal
        view
        returns (uint256 indexSet, uint256 payoutNumerator)
    {
        bytes32 collectionId = _getCollectionIdFromPosition(ct, collateral, positionId, conditionId);
        for (uint256 i = 0; i < 256; i++) {
            uint256 tryIndexSet = 1 << i;
            if (ct.getCollectionId(bytes32(0), conditionId, tryIndexSet) == collectionId) {
                return (tryIndexSet, ct.payoutNumerators(conditionId, i));
            }
        }
        revert("Could not determine outcome index for position");
    }

    function parseConfig(string memory json) internal pure virtual returns (Config memory) {
        Config memory config;

        config.wrapped1155Factory = abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address));
        config.conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));
        config.erc20 = abi.decode(vm.parseJson(json, ".erc20"), (address));
        config.amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        config.tokenData = abi.decode(vm.parseJson(json, ".tokenData"), (bytes));
        config.positionId = abi.decode(vm.parseJson(json, ".positionId"), (uint256));
        config.conditionId = abi.decode(vm.parseJson(json, ".conditionId"), (bytes32));
        config.collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));

        return config;
    }
}

contract UnwrapAndRedeemCheck is UnwrapAndRedeem {
    function run() external override {
        // Read config file
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        Config memory config = parseConfig(vm.readFile(configPath));

        address user = vm.envOr("USER", msg.sender);

        console.log("Checking unwrap and redeem status for user:", user);
        console.log("========================================");

        // Check wrapped token balance
        uint256 wrappedBalance = IERC20(config.erc20).balanceOf(user);
        console.log("Wrapped token balance:", wrappedBalance);
        console.log(
            wrappedBalance >= config.amount ? unicode"  ✅ Sufficient for unwrap" : unicode"  ❌ Insufficient for unwrap"
        );

        // Check ERC1155 balance
        console.log("ERC1155 balance:", IConditionalTokens(config.conditionalTokens).balanceOf(user, config.positionId));

        // Check if condition is resolved
        uint256 payoutDenominator = IConditionalTokens(config.conditionalTokens).payoutDenominator(config.conditionId);
        console.log("\nCondition resolution status:");
        console.log("  Payout denominator:", payoutDenominator);

        if (payoutDenominator == 0) {
            console.log(unicode"  ❌ Condition not resolved yet - cannot redeem");
            return;
        } else {
            console.log(unicode"  ✅ Condition resolved - can redeem");
        }

        // Outcome details and expected redemption
        {
            (uint256 indexSet, uint256 payoutNumerator) = _locateIndexAndPayout(
                IConditionalTokens(config.conditionalTokens),
                IERC20(config.collateralToken),
                config.positionId,
                config.conditionId
            );

            console.log("\nOutcome information:");
            console.log("  Index set:", indexSet);
            console.log("  Payout numerator:", payoutNumerator);
            console.log("  Payout percentage:", (payoutNumerator * 100) / payoutDenominator, "%");

            if (wrappedBalance >= config.amount) {
                console.log("\nExpected redemption:");
                console.log("  Amount to unwrap:", config.amount);
                console.log("  Expected collateral:", (config.amount * payoutNumerator) / payoutDenominator);
            }
        }

        // Check collateral balance
        console.log("\nCurrent collateral balance:", IERC20(config.collateralToken).balanceOf(user));
    }
}
