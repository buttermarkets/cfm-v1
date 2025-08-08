// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";
import {IUniswapV2Router02} from "src/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "src/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "src/interfaces/IUniswapV2Pair.sol";
import {InvalidlessConditionalScalarMarket} from "src/invalidless/InvalidlessConditionalScalarMarket.sol";

contract SplitAndAddLiquidity is Script {
    struct Config {
        address icsmAddress;
        uint256 depositAmount;
        address collateralToken;
        address conditionalTokens;
        address wrapped1155Factory;
        address uniswapV2Router;
        address uniswapV2Factory;
        uint256 deadline; // Optional: deadline for adding liquidity
        uint256 amountAMin; // Optional: minimum amount of token A
        uint256 amountBMin; // Optional: minimum amount of token B
    }

    function run() external {
        // Read config file path from environment variable
        require(
            bytes(vm.envString("LIQUIDITY_CONFIG_PATH")).length > 0,
            "LIQUIDITY_CONFIG_PATH environment variable must be set"
        );

        // Read and parse config file
        Config memory config = parseConfig(vm.readFile(vm.envString("LIQUIDITY_CONFIG_PATH")));

        // Validate configuration
        _validateConfig(config);

        // ctParams returns a tuple when accessed as a public variable
        (, bytes32 conditionId,,) = InvalidlessConditionalScalarMarket(config.icsmAddress).ctParams();

        console.log("=== Split and Add Liquidity ===");
        console.log("ICSM Address:", config.icsmAddress);
        console.log("Condition ID:", vm.toString(conditionId));
        console.log("Deposit Amount:", config.depositAmount);

        // Check if we should only display info
        if (_handleZeroDeposit(config)) {
            return;
        }

        // If depositAmount is set, proceed with liquidity operations
        console.log(unicode"\n✓ Deposit amount is set, proceeding with liquidity operations...\n");

        vm.startBroadcast();

        // Step 1: Approve ConditionalTokens to spend collateral
        IERC20(config.collateralToken).approve(config.conditionalTokens, config.depositAmount);
        console.log(unicode"✓ Approved ConditionalTokens to spend collateral");

        // Step 2: Split collateral into conditional tokens
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // Outcome 0 (short)
        partition[1] = 2; // Outcome 1 (long)

        IConditionalTokens(config.conditionalTokens).splitPosition(
            IERC20(config.collateralToken),
            bytes32(0), // parentCollectionId
            conditionId,
            partition,
            config.depositAmount
        );
        console.log(unicode"✓ Split collateral into conditional tokens");

        // Step 3: Wrap tokens and add liquidity
        uint256 liquidity = _wrapAndAddLiquidity(config, conditionId, partition);

        vm.stopBroadcast();

        // Log summary
        console.log(unicode"\n=== Summary ===");
        console.log("ICSM Address:", config.icsmAddress);
        console.log("LP Tokens:", liquidity);
    }

    function _handleZeroDeposit(Config memory config) internal view returns (bool) {
        if (config.depositAmount == 0) {
            console.log(unicode"\n⚠️  Deposit amount is 0 or not set");
            console.log("    No liquidity operations will be performed.");
            console.log("\n=== Market Information ===");

            // Get token addresses for display only
            (,,,, IERC20 existingShort, IERC20 existingLong) =
                InvalidlessConditionalScalarMarket(config.icsmAddress).wrappedCTData();

            console.log("Short Token:", address(existingShort));
            console.log("Long Token:", address(existingLong));

            _displayPairInfo(config, address(existingShort), address(existingLong));

            return true;
        }
        return false;
    }

    function _validateConfig(Config memory config) internal pure {
        require(config.icsmAddress != address(0), "Invalid ICSM address");
        // Note: depositAmount can be 0 to just check market info
        require(config.collateralToken != address(0), "Invalid collateral token");
        require(config.conditionalTokens != address(0), "Invalid conditional tokens");
        require(config.wrapped1155Factory != address(0), "Invalid wrapped1155 factory");
        require(config.uniswapV2Router != address(0), "Invalid Uniswap V2 router");
        require(config.uniswapV2Factory != address(0), "Invalid Uniswap V2 factory");
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

    function _wrapAndAddLiquidity(Config memory config, bytes32 conditionId, uint256[] memory partition)
        internal
        returns (uint256 liquidity)
    {
        // Calculate position IDs
        (uint256 shortPositionId, uint256 longPositionId) = _calculatePositionIds(config, conditionId, partition);

        // Approve Wrapped1155Factory
        IConditionalTokens(config.conditionalTokens).setApprovalForAll(config.wrapped1155Factory, true);
        console.log(unicode"✓ Approved Wrapped1155Factory");

        // Wrap tokens and get addresses
        (address shortToken, address longToken) = _performWrapping(config, shortPositionId, longPositionId);

        // Add liquidity
        liquidity = _addLiquidity(config, shortToken, longToken);

        // Log pair info
        console.log("Short Token:", shortToken);
        console.log("Long Token:", longToken);
        console.log("Pair Address:", _getOrCreatePair(config, shortToken, longToken));
    }

    function _performWrapping(Config memory config, uint256 shortPositionId, uint256 longPositionId)
        internal
        returns (address shortToken, address longToken)
    {
        // Get wrapped token data from ICSM
        (bytes memory shortData, bytes memory longData,,, IERC20 existingShort, IERC20 existingLong) =
            InvalidlessConditionalScalarMarket(config.icsmAddress).wrappedCTData();

        shortToken = address(existingShort);
        longToken = address(existingLong);

        console.log("  Using wrapped short token:", shortToken);
        console.log("  Using wrapped long token:", longToken);

        // Wrap the tokens
        _wrapTokens(config, shortPositionId, longPositionId, shortToken, longToken, shortData, longData);
    }

    function _addLiquidity(Config memory config, address shortToken, address longToken)
        internal
        returns (uint256 liquidity)
    {
        // Approve router to spend tokens
        IERC20(shortToken).approve(config.uniswapV2Router, config.depositAmount);
        IERC20(longToken).approve(config.uniswapV2Router, config.depositAmount);
        console.log(unicode"✓ Approved router to spend tokens");

        // Add liquidity
        (,, liquidity) = IUniswapV2Router02(config.uniswapV2Router).addLiquidity(
            shortToken,
            longToken,
            config.depositAmount,
            config.depositAmount,
            config.amountAMin,
            config.amountBMin,
            msg.sender,
            config.deadline > 0 ? config.deadline : block.timestamp + 30 minutes
        );

        console.log(unicode"✓ Added liquidity to Uniswap V2 pool");
        console.log(unicode"  LP tokens received:", liquidity);
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
        // Check current wrapped balances
        uint256 shortWrappedBalance = IERC20(shortToken).balanceOf(msg.sender);
        uint256 longWrappedBalance = IERC20(longToken).balanceOf(msg.sender);

        // Transfer ERC1155 tokens to factory to get wrapped tokens
        // The factory will mint wrapped tokens to msg.sender
        if (shortWrappedBalance < config.depositAmount) {
            uint256 toWrap = config.depositAmount - shortWrappedBalance;
            IConditionalTokens(config.conditionalTokens).safeTransferFrom(
                msg.sender, config.wrapped1155Factory, shortPositionId, toWrap, shortData
            );
            console.log(unicode"✓ Wrapped short tokens:", toWrap);
        }

        if (longWrappedBalance < config.depositAmount) {
            uint256 toWrap = config.depositAmount - longWrappedBalance;
            IConditionalTokens(config.conditionalTokens).safeTransferFrom(
                msg.sender, config.wrapped1155Factory, longPositionId, toWrap, longData
            );
            console.log(unicode"✓ Wrapped long tokens:", toWrap);
        }
    }

    function _getOrCreatePair(Config memory config, address shortToken, address longToken)
        internal
        returns (address pairAddress)
    {
        IUniswapV2Factory factory = IUniswapV2Factory(config.uniswapV2Factory);

        pairAddress = factory.getPair(shortToken, longToken);

        if (pairAddress == address(0)) {
            pairAddress = factory.createPair(shortToken, longToken);
            console.log(unicode"✓ Created new Uniswap pair:", pairAddress);
        } else {
            console.log(unicode"  Using existing pair:", pairAddress);
        }
    }

    function _displayPairInfo(Config memory config, address shortToken, address longToken) internal view {
        address pairAddress = IUniswapV2Factory(config.uniswapV2Factory).getPair(shortToken, longToken);

        if (pairAddress != address(0)) {
            console.log("Pair Address:", pairAddress);

            // Get pair reserves
            IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

            if (pair.token0() == shortToken) {
                console.log("  Short Reserve:", uint256(reserve0));
                console.log("  Long Reserve:", uint256(reserve1));
            } else {
                console.log("  Short Reserve:", uint256(reserve1));
                console.log("  Long Reserve:", uint256(reserve0));
            }

            uint256 totalSupply = pair.totalSupply();
            console.log("  LP Total Supply:", totalSupply);
        } else {
            console.log(unicode"⚠️  No liquidity pair exists yet");
        }
    }

    function parseConfig(string memory json) internal pure returns (Config memory) {
        Config memory config;

        // Required fields
        config.icsmAddress = vm.parseJsonAddress(json, ".icsmAddress");

        // depositAmount is optional - defaults to 0 if not provided
        try vm.parseJsonUint(json, ".depositAmount") returns (uint256 depositAmount) {
            config.depositAmount = depositAmount;
        } catch {
            config.depositAmount = 0;
        }

        config.collateralToken = vm.parseJsonAddress(json, ".collateralToken");
        config.conditionalTokens = vm.parseJsonAddress(json, ".conditionalTokens");
        config.wrapped1155Factory = vm.parseJsonAddress(json, ".wrapped1155Factory");
        config.uniswapV2Router = vm.parseJsonAddress(json, ".uniswapV2Router");
        config.uniswapV2Factory = vm.parseJsonAddress(json, ".uniswapV2Factory");

        // Optional fields with defaults
        try vm.parseJsonUint(json, ".deadline") returns (uint256 deadline) {
            config.deadline = deadline;
        } catch {
            config.deadline = 0; // Will default to block.timestamp + 30 minutes
        }

        try vm.parseJsonUint(json, ".amountAMin") returns (uint256 amountAMin) {
            config.amountAMin = amountAMin;
        } catch {
            config.amountAMin = 0; // Accept any amount for initial liquidity
        }

        try vm.parseJsonUint(json, ".amountBMin") returns (uint256 amountBMin) {
            config.amountBMin = amountBMin;
        } catch {
            config.amountBMin = 0; // Accept any amount for initial liquidity
        }

        return config;
    }
}
