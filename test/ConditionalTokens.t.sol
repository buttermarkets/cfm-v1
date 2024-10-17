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
        conditionalTokens = new ConditionalTokens();

        // If you're using a mock ERC20 token, initialize it here
        // mockERC20 = new MockERC20("Mock Token", "MTK", 18);
        // mockERC20.mint(address(this), 1000000 * 10**18);
    }

    function testInitialState() public {
        assertEq(conditionalTokens.balanceOf(owner, 0), 0);
        assertEq(conditionalTokens.balanceOf(user1, 0), 0);
        assertEq(conditionalTokens.balanceOf(owner, 1), 0);
    }

    function testFailRedeemPositionsBeforeReportingPayouts() public {
        // Prepare a condition
        bytes32 questionId = bytes32("Test Question");
        uint256 outcomeSlotCount = 2;
        conditionalTokens.prepareCondition(address(this), questionId, outcomeSlotCount);
        bytes32 conditionId = conditionalTokens.getConditionId(address(this), questionId, outcomeSlotCount);

        // Create a position ID
        uint256 indexSet = 1; // Representing the first outcome
        bytes32 collectionId = conditionalTokens.getCollectionId(bytes32(0), conditionId, indexSet);
        uint256 positionId = conditionalTokens.getPositionId(IERC20(address(this)), collectionId);

        // Increase the gas limit for this test
        vm.txGasPrice(0);
        vm.prank(address(this));

        // Mint tokens by splitting position
        uint256 mintAmount = 1000;
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        conditionalTokens.splitPosition(IERC20(address(this)), bytes32(0), conditionId, partition, mintAmount);

        // Attempt to redeem positions before reporting payouts (should fail)
        conditionalTokens.redeemPositions(IERC20(address(this)), bytes32(0), conditionId, partition);
    }
}
