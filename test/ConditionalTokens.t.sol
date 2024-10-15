// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std-1.9.3/src/Test.sol";
import "../src/ConditionalTokens.sol";

contract ConditionalTokensTest is Test {
    ConditionalTokens public conditionalTokens;
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        conditionalTokens = new ConditionalTokens("URI");
    }

    function testInitialState() public {
        assertEq(conditionalTokens.balanceOf(owner, 0), 0);
        assertEq(conditionalTokens.balanceOf(user1, 0), 0);
        assertEq(conditionalTokens.balanceOf(owner, 1), 0);
    }



    function testTransfer(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount <= type(uint256).max);
        vm.assume(transferAmount > 0 && transferAmount <= mintAmount);

        // Prepare a condition
        bytes32 questionId = bytes32("Test Question");
        uint256 outcomeSlotCount = 2;
        conditionalTokens.prepareCondition(address(this), questionId, outcomeSlotCount);
        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, outcomeSlotCount);

        // Create a position ID
        uint256 indexSet = 1; // Representing the first outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = conditionalTokens.getPositionId(IERC20(address(this)), collectionId);

        // Mint tokens by splitting position
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(IERC20(address(this)), bytes32(0), conditionId, partition, mintAmount);

        // Transfer tokens
        vm.prank(address(this));
        conditionalTokens.safeTransferFrom(address(this), user2, positionId, transferAmount, "");

        // Check balances
        assertEq(conditionalTokens.balanceOf(address(this), positionId), mintAmount - transferAmount);
        assertEq(conditionalTokens.balanceOf(user2, positionId), transferAmount);
    }

    function testApproveAndTransferFrom(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount <= type(uint256).max);
        vm.assume(transferAmount > 0 && transferAmount <= mintAmount);

        // Prepare a condition
        bytes32 questionId = bytes32("Test Question");
        uint256 outcomeSlotCount = 2;
        conditionalTokens.prepareCondition(address(this), questionId, outcomeSlotCount);
        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, outcomeSlotCount);

        // Create a position ID
        uint256 indexSet = 1; // Representing the first outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = conditionalTokens.getPositionId(IERC20(address(this)), collectionId);

        // Mint tokens by splitting position
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(IERC20(address(this)), bytes32(0), conditionId, partition, mintAmount);

        // Approve
        vm.prank(address(this));
        conditionalTokens.setApprovalForAll(user2, true);
        assertTrue(conditionalTokens.isApprovedForAll(address(this), user2));

        // Transfer
        vm.prank(user2);
        conditionalTokens.safeTransferFrom(address(this), user1, positionId, transferAmount, "");

        // Check balances
        assertEq(conditionalTokens.balanceOf(address(this), positionId), mintAmount - transferAmount);
        assertEq(conditionalTokens.balanceOf(user1, positionId), transferAmount);
    }

    function testFailTransferInsufficientBalance(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint256).max);
        vm.assume(transferAmount > mintAmount);

        // Prepare a condition and create a position ID
        bytes32 questionId = bytes32("Test Question");
        uint256 outcomeSlotCount = 2;
        conditionalTokens.prepareCondition(address(this), questionId, outcomeSlotCount);
        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, outcomeSlotCount);
        uint256 indexSet = 1; // Representing the first outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = conditionalTokens.getPositionId(IERC20(address(this)), collectionId);

        // Mint tokens by splitting position
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(IERC20(address(this)), bytes32(0), conditionId, partition, mintAmount);

        // Attempt to transfer more than the minted amount
        vm.prank(address(this));
        conditionalTokens.safeTransferFrom(address(this), user2, positionId, transferAmount, "");
    }

    function testFailTransferFromInsufficientAllowance(uint256 mintAmount, uint256 approveAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint256).max);
        vm.assume(approveAmount > 0 && approveAmount < mintAmount);
        vm.assume(transferAmount > approveAmount);

        // Prepare a condition and create a position ID
        bytes32 questionId = bytes32("Test Question");
        uint256 outcomeSlotCount = 2;
        conditionalTokens.prepareCondition(address(this), questionId, outcomeSlotCount);
        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, outcomeSlotCount);
        uint256 indexSet = 1; // Representing the first outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = conditionalTokens.getPositionId(IERC20(address(this)), collectionId);

        // Mint tokens by splitting position
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(IERC20(address(this)), bytes32(0), conditionId, partition, mintAmount);

        // Transfer tokens to user1
        vm.prank(address(this));
        conditionalTokens.safeTransferFrom(address(this), user1, positionId, mintAmount, "");

        // Approve user2 to spend tokens on behalf of user1
        vm.prank(user1);
        conditionalTokens.setApprovalForAll(user2, true);

        // Attempt to transfer more than the approved amount
        vm.prank(user2);
        conditionalTokens.safeTransferFrom(user1, address(this), positionId, transferAmount, "");
    }
}
