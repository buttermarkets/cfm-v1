// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {InvalidlessConditionalScalarMarket} from "src/invalidless/InvalidlessConditionalScalarMarket.sol";

contract SplitAndWrapICSM is Script {
    struct Config {
        address icsmAddress;
        uint256 amount;
        address collateralToken;
        address conditionalTokens;
        address wrapped1155Factory;
    }

    function run() external {
        // Read config file path from environment variable
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        // Read and parse config file
        Config memory config = parseConfig(vm.readFile(configPath));

        // Validate inputs
        require(config.icsmAddress != address(0), "Invalid ICSM address");
        require(config.amount > 0, "Amount must be greater than 0");
        require(config.collateralToken != address(0), "Invalid collateral address");
        require(config.conditionalTokens != address(0), "Invalid conditional tokens address");
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155 factory address");

        // Get ICSM contract
        InvalidlessConditionalScalarMarket icsm = InvalidlessConditionalScalarMarket(config.icsmAddress);

        // Get condition ID and wrapped token data from ICSM
        (, bytes32 conditionId,,) = icsm.ctParams();
        (bytes memory shortData, bytes memory longData,,, IERC20 shortToken, IERC20 longToken) = icsm.wrappedCTData();

        console.log("Splitting and wrapping for ICSM:");
        console.log("  ICSM Address:", config.icsmAddress);
        console.log("  Collateral:", config.collateralToken);
        console.log("  Amount:", config.amount);
        console.log("  Condition ID:", vm.toString(conditionId));

        // Create partition for split (2 outcomes: short and long)
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // Short outcome
        partition[1] = 2; // Long outcome

        vm.startBroadcast();

        // Approve conditional tokens to spend collateral
        IERC20(config.collateralToken).approve(config.conditionalTokens, config.amount);
        console.log("Approved ConditionalTokens to spend collateral");

        // Split position
        IConditionalTokens(config.conditionalTokens).splitPosition(
            IERC20(config.collateralToken),
            bytes32(0), // parentCollectionId = 0 for ICSM standalone markets
            conditionId,
            partition,
            config.amount
        );
        console.log("Split position completed");

        // Calculate position IDs
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);
        bytes32 shortCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[0]);
        bytes32 longCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[1]);
        uint256 shortPositionId = ct.getPositionId(IERC20(config.collateralToken), shortCollectionId);
        uint256 longPositionId = ct.getPositionId(IERC20(config.collateralToken), longCollectionId);

        console.log("Position IDs:");
        console.log("  Short:", shortPositionId);
        console.log("  Long:", longPositionId);

        // Approve wrapped1155Factory to transfer the position tokens
        ct.setApprovalForAll(config.wrapped1155Factory, true);
        console.log("Approved Wrapped1155Factory for all tokens");

        // Check current wrapped balances
        uint256 shortWrappedBalance = shortToken.balanceOf(msg.sender);
        uint256 longWrappedBalance = longToken.balanceOf(msg.sender);

        // Wrap short tokens if needed
        if (shortWrappedBalance < config.amount) {
            uint256 toWrap = config.amount - shortWrappedBalance;
            ct.safeTransferFrom(msg.sender, config.wrapped1155Factory, shortPositionId, toWrap, shortData);
            console.log("Wrapped short tokens:", toWrap);
            console.log("  Short token address:", address(shortToken));
        }

        // Wrap long tokens if needed
        if (longWrappedBalance < config.amount) {
            uint256 toWrap = config.amount - longWrappedBalance;
            ct.safeTransferFrom(msg.sender, config.wrapped1155Factory, longPositionId, toWrap, longData);
            console.log("Wrapped long tokens:", toWrap);
            console.log("  Long token address:", address(longToken));
        }

        vm.stopBroadcast();

        // Show final balances
        uint256 finalShortBalance = shortToken.balanceOf(msg.sender);
        uint256 finalLongBalance = longToken.balanceOf(msg.sender);

        console.log("\nSplit and wrap completed successfully!");
        console.log("Final wrapped token balances:");
        console.log("  Short tokens:", finalShortBalance);
        console.log("  Long tokens:", finalLongBalance);
    }

    function parseConfig(string memory json) internal pure returns (Config memory) {
        Config memory config;

        // Parse each field individually
        config.icsmAddress = abi.decode(vm.parseJson(json, ".icsmAddress"), (address));
        config.amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        config.collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));
        config.conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));
        config.wrapped1155Factory = abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address));

        return config;
    }
}

contract SplitAndWrapICSMCheck is Script {
    function run() external view {
        // Read config file
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        string memory json = vm.readFile(configPath);

        address icsmAddress = abi.decode(vm.parseJson(json, ".icsmAddress"), (address));
        uint256 amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        address collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));
        address conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));

        // Get ICSM data
        InvalidlessConditionalScalarMarket icsm = InvalidlessConditionalScalarMarket(icsmAddress);
        (, bytes32 conditionId,,) = icsm.ctParams();
        (,,,, IERC20 shortToken, IERC20 longToken) = icsm.wrappedCTData();

        address user = vm.envOr("USER", msg.sender);

        console.log("Checking split and wrap status for ICSM:");
        console.log("  User:", user);
        console.log("  ICSM:", icsmAddress);
        console.log("========================================");

        // Check collateral balance and allowance
        IERC20 collateral = IERC20(collateralToken);
        uint256 collateralBalance = collateral.balanceOf(user);
        uint256 collateralAllowance = collateral.allowance(user, conditionalTokens);

        console.log("Collateral:");
        console.log("  Balance:", collateralBalance);
        console.log("  Allowance:", collateralAllowance);
        console.log(collateralAllowance >= amount ? unicode"  ✅ Sufficient allowance" : unicode"  ❌ Insufficient allowance");

        // Check ERC1155 balances
        IConditionalTokens ct = IConditionalTokens(conditionalTokens);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        bytes32 shortCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[0]);
        bytes32 longCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[1]);
        uint256 shortPositionId = ct.getPositionId(collateral, shortCollectionId);
        uint256 longPositionId = ct.getPositionId(collateral, longCollectionId);

        uint256 shortERC1155Balance = ct.balanceOf(user, shortPositionId);
        uint256 longERC1155Balance = ct.balanceOf(user, longPositionId);

        console.log("\nERC1155 Positions:");
        console.log("  Short balance:", shortERC1155Balance);
        console.log("  Long balance:", longERC1155Balance);

        // Check wrapped token balances
        uint256 shortWrappedBalance = shortToken.balanceOf(user);
        uint256 longWrappedBalance = longToken.balanceOf(user);

        console.log("\nWrapped ERC20 Tokens:");
        console.log("  Short token:", address(shortToken));
        console.log("  Short balance:", shortWrappedBalance);
        console.log("  Long token:", address(longToken));
        console.log("  Long balance:", longWrappedBalance);

        // Check approval status
        bool isApproved = ct.isApprovedForAll(user, abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address)));
        console.log("\nWrapped1155Factory approval:", isApproved ? "✅ Approved" : "❌ Not approved");
    }
}
