// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

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
            collateralToken, bytes32(0), parent_condition_id, generateBasicPartition(2), AMOUNT
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
                generateBasicPartition(2),
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

    function generateBasicPartition(uint256 outcomeSlotCount) private pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }
}
