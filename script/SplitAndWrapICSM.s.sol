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
        _validateConfig(config);

        // Get condition ID from ICSM
        (, bytes32 conditionId,,) = InvalidlessConditionalScalarMarket(config.icsmAddress).ctParams();

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

        // Perform wrapping
        (address shortToken, address longToken) = _performWrapping(config, conditionId, partition);

        vm.stopBroadcast();

        // Show final balances
        _displayFinalBalances(shortToken, longToken);
    }

    function _validateConfig(Config memory config) internal pure {
        require(config.icsmAddress != address(0), "Invalid ICSM address");
        require(config.amount > 0, "Amount must be greater than 0");
        require(config.collateralToken != address(0), "Invalid collateral address");
        require(config.conditionalTokens != address(0), "Invalid conditional tokens address");
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155 factory address");
    }

    function _calculatePositionIds(Config memory config, bytes32 conditionId, uint256[] memory partition)
        internal
        view
        returns (uint256 shortPositionId, uint256 longPositionId)
    {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);

        bytes32 shortCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[0]);
        bytes32 longCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[1]);

        shortPositionId = ct.getPositionId(IERC20(config.collateralToken), shortCollectionId);
        longPositionId = ct.getPositionId(IERC20(config.collateralToken), longCollectionId);

        console.log("Position IDs:");
        console.log("  Short:", shortPositionId);
        console.log("  Long:", longPositionId);
    }

    function _performWrapping(Config memory config, bytes32 conditionId, uint256[] memory partition)
        internal
        returns (address shortToken, address longToken)
    {
        // Calculate position IDs
        (uint256 shortPositionId, uint256 longPositionId) = _calculatePositionIds(config, conditionId, partition);

        // Approve wrapped1155Factory to transfer the position tokens
        IConditionalTokens(config.conditionalTokens).setApprovalForAll(config.wrapped1155Factory, true);
        console.log("Approved Wrapped1155Factory for all tokens");

        // Get wrapped token data from ICSM
        (bytes memory shortData, bytes memory longData,,, IERC20 existingShort, IERC20 existingLong) =
            InvalidlessConditionalScalarMarket(config.icsmAddress).wrappedCTData();

        shortToken = address(existingShort);
        longToken = address(existingLong);

        // Wrap the tokens
        _wrapTokens(config, shortPositionId, longPositionId, shortToken, longToken, shortData, longData);

        return (shortToken, longToken);
    }

    function _wrapTokens(
        Config memory config,
        uint256 shortPositionId,
        uint256 longPositionId,
        address shortToken,
        address longToken,
        bytes memory shortData,
        bytes memory longData
    ) internal {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);

        // Check current wrapped balances
        uint256 shortWrappedBalance = IERC20(shortToken).balanceOf(msg.sender);
        uint256 longWrappedBalance = IERC20(longToken).balanceOf(msg.sender);

        // Wrap short tokens if needed
        if (shortWrappedBalance < config.amount) {
            uint256 toWrap = config.amount - shortWrappedBalance;
            ct.safeTransferFrom(msg.sender, config.wrapped1155Factory, shortPositionId, toWrap, shortData);
            console.log("Wrapped short tokens:", toWrap);
            console.log("  Short token address:", shortToken);
        }

        // Wrap long tokens if needed
        if (longWrappedBalance < config.amount) {
            uint256 toWrap = config.amount - longWrappedBalance;
            ct.safeTransferFrom(msg.sender, config.wrapped1155Factory, longPositionId, toWrap, longData);
            console.log("Wrapped long tokens:", toWrap);
            console.log("  Long token address:", longToken);
        }
    }

    function _displayFinalBalances(address shortToken, address longToken) internal view {
        uint256 finalShortBalance = IERC20(shortToken).balanceOf(msg.sender);
        uint256 finalLongBalance = IERC20(longToken).balanceOf(msg.sender);

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
    struct CheckConfig {
        address icsmAddress;
        uint256 amount;
        address collateralToken;
        address conditionalTokens;
        address wrapped1155Factory;
        address user;
    }

    function run() external view {
        // Read config file
        string memory configPath = vm.envString("CONFIG_PATH");
        require(bytes(configPath).length > 0, "CONFIG_PATH environment variable must be set");

        string memory json = vm.readFile(configPath);

        CheckConfig memory config;
        config.icsmAddress = abi.decode(vm.parseJson(json, ".icsmAddress"), (address));
        config.amount = abi.decode(vm.parseJson(json, ".amount"), (uint256));
        config.collateralToken = abi.decode(vm.parseJson(json, ".collateralToken"), (address));
        config.conditionalTokens = abi.decode(vm.parseJson(json, ".conditionalTokens"), (address));
        config.wrapped1155Factory = abi.decode(vm.parseJson(json, ".wrapped1155Factory"), (address));
        config.user = vm.envOr("USER", msg.sender);

        console.log("Checking split and wrap status for ICSM:");
        console.log("  User:", config.user);
        console.log("  ICSM:", config.icsmAddress);
        console.log("========================================");

        // Check collateral
        _checkCollateral(config);

        // Check positions and wrapped tokens
        _checkPositionsAndTokens(config);
    }

    function _checkCollateral(CheckConfig memory config) internal view {
        IERC20 collateral = IERC20(config.collateralToken);
        uint256 collateralBalance = collateral.balanceOf(config.user);
        uint256 collateralAllowance = collateral.allowance(config.user, config.conditionalTokens);

        console.log("Collateral:");
        console.log("  Balance:", collateralBalance);
        console.log("  Allowance:", collateralAllowance);
        console.log(
            collateralAllowance >= config.amount
                ? unicode"  ✅ Sufficient allowance"
                : unicode"  ❌ Insufficient allowance"
        );
    }

    function _checkPositionsAndTokens(CheckConfig memory config) internal view {
        // Get ICSM data
        (, bytes32 conditionId,,) = InvalidlessConditionalScalarMarket(config.icsmAddress).ctParams();

        // Check ERC1155 balances
        _checkERC1155Balances(config, conditionId);

        // Check wrapped tokens
        _checkWrappedTokens(config);

        // Check approval status
        _checkApproval(config);
    }

    function _checkERC1155Balances(CheckConfig memory config, bytes32 conditionId) internal view {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        bytes32 shortCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[0]);
        bytes32 longCollectionId = ct.getCollectionId(bytes32(0), conditionId, partition[1]);

        uint256 shortPositionId = ct.getPositionId(IERC20(config.collateralToken), shortCollectionId);
        uint256 longPositionId = ct.getPositionId(IERC20(config.collateralToken), longCollectionId);

        uint256 shortERC1155Balance = ct.balanceOf(config.user, shortPositionId);
        uint256 longERC1155Balance = ct.balanceOf(config.user, longPositionId);

        console.log("\nERC1155 Positions:");
        console.log("  Short balance:", shortERC1155Balance);
        console.log("  Long balance:", longERC1155Balance);
    }

    function _checkWrappedTokens(CheckConfig memory config) internal view {
        (,,,, IERC20 shortToken, IERC20 longToken) =
            InvalidlessConditionalScalarMarket(config.icsmAddress).wrappedCTData();

        uint256 shortWrappedBalance = shortToken.balanceOf(config.user);
        uint256 longWrappedBalance = longToken.balanceOf(config.user);

        console.log("\nWrapped ERC20 Tokens:");
        console.log("  Short token:", address(shortToken));
        console.log("  Short balance:", shortWrappedBalance);
        console.log("  Long token:", address(longToken));
        console.log("  Long balance:", longWrappedBalance);
    }

    function _checkApproval(CheckConfig memory config) internal view {
        IConditionalTokens ct = IConditionalTokens(config.conditionalTokens);
        bool isApproved = ct.isApprovedForAll(config.user, config.wrapped1155Factory);
        console.log("\nWrapped1155Factory approval:", isApproved ? unicode"✅ Approved" : unicode"❌ Not approved");
    }
}
