// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20Errors} from "@openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import "../src/butter-v1/ConditionalScalarMarket.sol";
import "../src/butter-v1/CFMRealityAdapter.sol";
import "../src/ConditionalTokens.sol";
import "../src/Wrapped1155Factory.sol";
import "./FakeRealityETH.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test Token", "TST") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// TODO: fuzz
contract ConditionalScalarMarketTest is Test {
    ConditionalScalarMarket market;
    ConditionalTokens conditionalTokens;
    Wrapped1155Factory wrapped1155Factory;
    CFMRealityAdapter oracleAdapter;
    TestToken collateralToken;
    FakeRealityETH realityETH;

    address user = address(1);
    address arbitrator = address(2);
    uint256 constant AMOUNT = 100e18;
    // We use a known questionId for the parent condition to make the setup explicit
    bytes32 constant PARENT_QUESTION_ID = bytes32(uint256(4242123123));
    bytes32 parent_condition_id;
    //bytes32 constant PARENT_CONDITION_ID = keccak256(abi.encodePacked(address(2), PARENT_QUESTION_ID, uint256(2)));

    uint256 parentPositionId;
    bytes32 parentCollectionId;

    function setUp() public {
        // Deploy core infrastructure
        collateralToken = new TestToken();
        realityETH = new FakeRealityETH();
        conditionalTokens = new ConditionalTokens();
        wrapped1155Factory = new Wrapped1155Factory();

        oracleAdapter = new CFMRealityAdapter(IRealityETH(address(realityETH)), arbitrator, 2, 1, uint32(7 days), 1e18);

        // Label addresses for clarity in test outputs.
        vm.label(user, "User");
        vm.label(arbitrator, "Arbitrator");
        vm.label(address(collateralToken), "$COL");
        vm.label(address(realityETH), "RealityETH");
        vm.label(address(conditionalTokens), "ConditionalTokens");
        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
        vm.label(address(oracleAdapter), "CFMRealityAdapter");

        collateralToken.mint(user, AMOUNT);

        // First, prepare the parent condition properly
        // We use arbitrator as the oracle for the parent condition
        conditionalTokens.prepareCondition(
            address(oracleAdapter), // Oracle for parent condition
            PARENT_QUESTION_ID, // Question ID for parent condition
            2 // Binary outcome for parent condition
        );
        parent_condition_id = conditionalTokens.getConditionId(address(oracleAdapter), PARENT_QUESTION_ID, 2);

        // Setup market parameters
        CFMConditionalQuestionParams memory questionParams = CFMConditionalQuestionParams({
            metricName: "Market Cap",
            startDate: "2024-01-01",
            endDate: "2024-12-31",
            minValue: 0,
            maxValue: 100e18,
            openingTime: uint32(block.timestamp + 1 days)
        });

        ConditionalMarketCTParams memory ctParams = ConditionalMarketCTParams({
            parentConditionId: parent_condition_id,
            outcomeName: "Market Cap Q1",
            outcomeIndex: 0,
            collateralToken: IERC20(address(collateralToken))
        });

        // Deploy market
        market =
            new ConditionalScalarMarket(oracleAdapter, conditionalTokens, wrapped1155Factory, questionParams, ctParams);

        // Setup parent position state - now with real prepared condition
        parentCollectionId = conditionalTokens.getCollectionId(bytes32(0), parent_condition_id, 1 << 0);
        parentPositionId = conditionalTokens.getPositionId(collateralToken, parentCollectionId);

        // Give user initial parent position tokens
        vm.startPrank(user);
        collateralToken.approve(address(conditionalTokens), AMOUNT);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), parent_condition_id, _generateBasicPartition(2), AMOUNT
        );
        vm.stopPrank();
    }

    function testSplit() public {
        // Arrange
        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);

        // Expect the splitPosition call with exact parameters
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ConditionalTokens.splitPosition.selector,
                address(collateralToken),
                parentCollectionId,
                market.conditionId(),
                _generateBasicPartition(2),
                AMOUNT
            )
        );

        // Act
        market.split(AMOUNT);

        // Assert
        // 1. Parent token consumed
        assertEq(
            conditionalTokens.balanceOf(user, parentPositionId),
            initialParentBalance - AMOUNT,
            "Parent tokens not consumed correctly"
        );

        // 2. ERC1155 tokens assigned to factory
        assertEq(
            conditionalTokens.balanceOf(address(wrapped1155Factory), market.shortPositionId()),
            AMOUNT,
            "Short ERC1155 not assigned to factory"
        );
        assertEq(
            conditionalTokens.balanceOf(address(wrapped1155Factory), market.longPositionId()),
            AMOUNT,
            "Long ERC1155 not assigned to factory"
        );

        // 3. Wrapped ERC20 tokens sent to user
        assertEq(market.wrappedShort().balanceOf(user), AMOUNT, "User did not receive short tokens");
        assertEq(market.wrappedLong().balanceOf(user), AMOUNT, "User did not receive long tokens");

        vm.stopPrank();
    }

    function testSplitInsufficientBalance() public {
        uint256 userBalance = conditionalTokens.balanceOf(user, parentPositionId);
        uint256 tooMuch = userBalance + 1;

        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);

        // Should be:
        bytes memory customError = abi.encodeWithSignature(
            "ERC1155InsufficientBalance(address,uint256,uint256,uint256)",
            user, // account lacking balance
            userBalance, // current balance
            tooMuch, // amount needed
            parentPositionId // token id
        );
        vm.expectRevert(customError);

        market.split(tooMuch);
        vm.stopPrank();
    }

    // TODO: fuzz (amount…)
    function testMerge() public {
        // Arrange
        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);
        market.split(AMOUNT);
        market.wrappedShort().approve(address(market), AMOUNT);
        market.wrappedLong().approve(address(market), AMOUNT);

        // Verify state before merge
        assertEq(
            conditionalTokens.balanceOf(user, parentPositionId),
            initialParentBalance - AMOUNT,
            "Initial parent balance incorrect"
        );
        assertEq(market.wrappedShort().balanceOf(user), AMOUNT, "Initial short balance incorrect");
        assertEq(market.wrappedLong().balanceOf(user), AMOUNT, "Initial long balance incorrect");

        // Expect the merge call
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                ConditionalTokens.mergePositions.selector,
                address(collateralToken),
                parentCollectionId,
                market.conditionId(),
                _generateBasicPartition(2),
                AMOUNT
            )
        );

        // Act
        market.merge(AMOUNT);

        // Assert final state
        assertEq(
            conditionalTokens.balanceOf(user, parentPositionId),
            initialParentBalance,
            "Parent tokens not retrieved correctly"
        );
        assertEq(
            conditionalTokens.balanceOf(address(wrapped1155Factory), market.shortPositionId()),
            0,
            "Short ERC1155 not returned by factory"
        );
        assertEq(
            conditionalTokens.balanceOf(address(wrapped1155Factory), market.longPositionId()),
            0,
            "Long ERC1155 not returned by factory"
        );
        assertEq(market.wrappedShort().balanceOf(user), 0, "User did not return short tokens");
        assertEq(market.wrappedLong().balanceOf(user), 0, "User did not return long tokens");

        vm.stopPrank();
    }

    function testMergeInsufficientBalance() public {
        // First split some tokens
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);
        market.split(AMOUNT);
        market.wrappedShort().approve(address(market), type(uint256).max);
        market.wrappedLong().approve(address(market), type(uint256).max);

        // Try to merge more than we have
        uint256 tooMuch = AMOUNT + 1;

        // Expect revert on the first token transfer
        // The unwrap of the first ERC20 should fail since we don't have enough
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user, // from
                AMOUNT, // balance
                tooMuch // needed
            )
        );
        market.merge(tooMuch);
        vm.stopPrank();
    }

    function testMergeWithoutApproval() public {
        // First split tokens
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);
        market.split(AMOUNT);

        // Reset all approvals
        market.wrappedShort().approve(address(market), 0);
        market.wrappedLong().approve(address(market), 0);

        // Should fail when trying to transfer ERC20s without approval
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(market), 0, AMOUNT)
        );
        market.merge(AMOUNT);
        vm.stopPrank();
    }

    function testMergeZeroAmount() public {
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);

        // Zero amount merges should revert early
        vm.expectRevert("amount must be positive");
        market.merge(0);
        vm.stopPrank();
    }

    function testPartialMerge() public {
        // First split all tokens
        vm.startPrank(user);
        conditionalTokens.setApprovalForAll(address(market), true);
        market.split(AMOUNT);

        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
        uint256 mergeAmount = AMOUNT / 2;
        market.wrappedShort().approve(address(market), mergeAmount);
        market.wrappedLong().approve(address(market), mergeAmount);

        // Merge half the tokens
        market.merge(mergeAmount);

        // Assert partial balances
        assertEq(market.wrappedShort().balanceOf(user), AMOUNT - mergeAmount, "Wrong remaining short balance");
        assertEq(market.wrappedLong().balanceOf(user), AMOUNT - mergeAmount, "Wrong remaining long balance");
        assertEq(
            conditionalTokens.balanceOf(user, parentPositionId),
            initialParentBalance + mergeAmount,
            "Wrong parent token balance after partial merge"
        );

        // Can still merge the rest
        market.wrappedShort().approve(address(market), mergeAmount);
        market.wrappedLong().approve(address(market), mergeAmount);
        market.merge(AMOUNT - mergeAmount);
        assertEq(market.wrappedShort().balanceOf(user), 0, "Short balance not zero after full merge");
        assertEq(market.wrappedLong().balanceOf(user), 0, "Long balance not zero after full merge");

        vm.stopPrank();
    }

    function _generateBasicPartition(uint256 outcomeSlotCount) private pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }
}
