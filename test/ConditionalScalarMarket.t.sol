// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

//import "forge-std/src/Test.sol";
//import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
//import {IERC20Errors} from "@openzeppelin-contracts/interfaces/draft-IERC6093.sol";
//
//import "src/ConditionalScalarMarket.sol";
//import "src/FlatCFMRealityAdapter.sol";
//import "src/Types.sol";
//import "src/vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
//import "src/vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
//import "./FakeRealityETH.sol";
//
//contract TestToken is ERC20 {
//    constructor() ERC20("Test Token", "TST") {}
//
//    function mint(address to, uint256 amount) public {
//        _mint(to, amount);
//    }
//}
//
//// TODO: fuzz
//contract SplitMergeTest is Test {
//    ConditionalScalarMarket market;
//    ConditionalTokens conditionalTokens;
//    Wrapped1155Factory wrapped1155Factory;
//    FlatCFMRealityAdapter oracleAdapter;
//    TestToken collateralToken;
//    FakeRealityETH realityETH;
//
//    address user = address(1);
//    address arbitrator = address(2);
//    uint256 constant AMOUNT = 100e18;
//    // We use a known questionId for the parent condition to make the setup explicit
//    bytes32 constant PARENT_QUESTION_ID = bytes32(uint256(4242123123));
//    bytes32 decisionConditionId;
//
//    uint256 parentPositionId;
//    bytes32 parentCollectionId;
//
//    function setUp() public {
//        // Deploy core infrastructure
//        collateralToken = new TestToken();
//        realityETH = new FakeRealityETH();
//        conditionalTokens = new ConditionalTokens();
//        wrapped1155Factory = new Wrapped1155Factory();
//
//        oracleAdapter =
//            new FlatCFMRealityAdapter(IRealityETH(address(realityETH)), arbitrator, 2, 1, uint32(7 days), 1e18);
//
//        // Label addresses for clarity in test outputs.
//        vm.label(user, "User");
//        vm.label(arbitrator, "Arbitrator");
//        vm.label(address(collateralToken), "$COL");
//        vm.label(address(realityETH), "RealityETH");
//        vm.label(address(conditionalTokens), "ConditionalTokens");
//        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
//        vm.label(address(oracleAdapter), "FlatCFMRealityAdapter");
//
//        collateralToken.mint(user, AMOUNT);
//
//        // First, prepare the parent condition properly
//        // We use arbitrator as the oracle for the parent condition
//        conditionalTokens.prepareCondition(
//            address(oracleAdapter), // Oracle for parent condition
//            PARENT_QUESTION_ID, // Question ID for parent condition
//            2 // Binary outcome for parent condition
//        );
//        decisionConditionId = conditionalTokens.getConditionId(address(oracleAdapter), PARENT_QUESTION_ID, 2);
//
//        ConditionalScalarCTParams memory ctParams = ConditionalScalarCTParams({
//            parentConditionId: decisionConditionId,
//            outcomeName: "Market Cap Q1",
//            outcomeIndex: 0,
//            collateralToken: IERC20(address(collateralToken))
//        });
//
//        ScalarParams memory scalarParams = ScalarParams({minValue: 0, maxValue: 100e18});
//
//        // Prepare dummy ERC20 data and stub requireWrapped155.
//        bytes shortData = abi.encodePacked(toString31("Outcome-Short"), toString31("Outcome-ST"), uint8(18));
//        bytes longData = abi.encodePacked(toString31("Outcome-Long"), toString31("Outcome-LG"), uint8(18));
//
//        uint256 shortPositionId = 0;
//        uint256 longPositionId = 1;
//
//        vm.mockCall(
//            address(mockWrapped),
//            abi.encodeWithSelector(IWrapped1155Factory.requireWrapped1155.selector, mockCT, shortPositionId, shortData),
//            abi.encode(IERC20(makeAddr("wrappedShort")))
//        );
//
//        vm.mockCall(
//            address(mockWrapped),
//            abi.encodeWithSelector(IWrapped1155Factory.requireWrapped1155.selector, mockCT, longPositionId, longData),
//            abi.encode(IERC20(makeAddr("wrappedLong")))
//        );
//
//        WrappedConditionalTokensData memory wrappedCTData = WrappedConditionalTokensData({});
//
//        // Deploy market
//        market = new ConditionalScalarMarket(
//            oracleAdapter,
//            IConditionalTokens(address(conditionalTokens)),
//            IWrapped1155Factory(address(wrapped1155Factory)),
//            ctParams,
//            scalarParams,
//            wrappedCTData
//        );
//
//        // Setup parent position state - now with real prepared condition
//        parentCollectionId = conditionalTokens.getCollectionId(bytes32(0), decisionConditionId, 1 << 0);
//        parentPositionId = conditionalTokens.getPositionId(collateralToken, parentCollectionId);
//
//        // Give user initial parent position tokens
//        vm.startPrank(user);
//        collateralToken.approve(address(conditionalTokens), AMOUNT);
//        conditionalTokens.splitPosition(
//            collateralToken, bytes32(0), decisionConditionId, _generateBasicPartition(2), AMOUNT
//        );
//        vm.stopPrank();
//    }
//
//    function testSplit() public {
//        // Arrange
//        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//
//        // Expect the splitPosition call with exact parameters
//        vm.expectCall(
//            address(conditionalTokens),
//            abi.encodeWithSelector(
//                ConditionalTokens.splitPosition.selector,
//                address(collateralToken),
//                parentCollectionId,
//                market.conditionId(),
//                _generateBasicPartition(2),
//                AMOUNT
//            )
//        );
//
//        // Act
//        market.split(AMOUNT);
//
//        // Assert
//        // 1. Parent token consumed
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialParentBalance - AMOUNT,
//            "Parent tokens not consumed correctly"
//        );
//
//        // 2. ERC1155 tokens assigned to factory
//        assertEq(
//            conditionalTokens.balanceOf(address(wrapped1155Factory), market.shortPositionId()),
//            AMOUNT,
//            "Short ERC1155 not assigned to factory"
//        );
//        assertEq(
//            conditionalTokens.balanceOf(address(wrapped1155Factory), market.longPositionId()),
//            AMOUNT,
//            "Long ERC1155 not assigned to factory"
//        );
//
//        // 3. Wrapped ERC20 tokens sent to user
//        assertEq(market.wrappedShort().balanceOf(user), AMOUNT, "User did not receive short tokens");
//        assertEq(market.wrappedLong().balanceOf(user), AMOUNT, "User did not receive long tokens");
//
//        vm.stopPrank();
//    }
//
//    function testSplitInsufficientBalance() public {
//        uint256 userBalance = conditionalTokens.balanceOf(user, parentPositionId);
//        uint256 tooMuch = userBalance + 1;
//
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//
//        // Should be:
//        bytes memory customError = abi.encodeWithSignature(
//            "ERC1155InsufficientBalance(address,uint256,uint256,uint256)",
//            user, // account lacking balance
//            userBalance, // current balance
//            tooMuch, // amount needed
//            parentPositionId // token id
//        );
//        vm.expectRevert(customError);
//
//        market.split(tooMuch);
//        vm.stopPrank();
//    }
//
//    // TODO: fuzz (amount…)
//    function testMerge() public {
//        // Arrange
//        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        market.wrappedShort().approve(address(market), AMOUNT);
//        market.wrappedLong().approve(address(market), AMOUNT);
//
//        // Verify state before merge
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialParentBalance - AMOUNT,
//            "Initial parent balance incorrect"
//        );
//        assertEq(market.wrappedShort().balanceOf(user), AMOUNT, "Initial short balance incorrect");
//        assertEq(market.wrappedLong().balanceOf(user), AMOUNT, "Initial long balance incorrect");
//
//        // Expect the merge call
//        vm.expectCall(
//            address(conditionalTokens),
//            abi.encodeWithSelector(
//                ConditionalTokens.mergePositions.selector,
//                address(collateralToken),
//                parentCollectionId,
//                market.conditionId(),
//                _generateBasicPartition(2),
//                AMOUNT
//            )
//        );
//
//        // Act
//        market.merge(AMOUNT);
//
//        // Assert final state
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialParentBalance,
//            "Parent tokens not retrieved correctly"
//        );
//        assertEq(
//            conditionalTokens.balanceOf(address(wrapped1155Factory), market.shortPositionId()),
//            0,
//            "Short ERC1155 not returned by factory"
//        );
//        assertEq(
//            conditionalTokens.balanceOf(address(wrapped1155Factory), market.longPositionId()),
//            0,
//            "Long ERC1155 not returned by factory"
//        );
//        assertEq(market.wrappedShort().balanceOf(user), 0, "User did not return short tokens");
//        assertEq(market.wrappedLong().balanceOf(user), 0, "User did not return long tokens");
//
//        vm.stopPrank();
//    }
//
//    function testMergeInsufficientBalance() public {
//        // Arrange
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        market.wrappedShort().approve(address(market), type(uint256).max);
//        market.wrappedLong().approve(address(market), type(uint256).max);
//
//        // Try to merge more than we have
//        uint256 tooMuch = AMOUNT + 1;
//
//        // Expect revert on the first token transfer
//        // The unwrap of the first ERC20 should fail since we don't have enough
//        vm.expectRevert(
//            abi.encodeWithSelector(
//                IERC20Errors.ERC20InsufficientBalance.selector,
//                user, // from
//                AMOUNT, // balance
//                tooMuch // needed
//            )
//        );
//        market.merge(tooMuch);
//        vm.stopPrank();
//    }
//
//    function testMergeWithoutApproval() public {
//        // Arrange
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//
//        // Reset all approvals
//        market.wrappedShort().approve(address(market), 0);
//        market.wrappedLong().approve(address(market), 0);
//
//        // Should fail when trying to transfer ERC20s without approval
//        vm.expectRevert(
//            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(market), 0, AMOUNT)
//        );
//        market.merge(AMOUNT);
//        vm.stopPrank();
//    }
//
//    function testMergeZeroAmount() public {
//        // Arrange
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//
//        // Zero amount merges should revert early
//        vm.expectRevert("amount must be positive");
//        market.merge(0);
//        vm.stopPrank();
//    }
//
//    function testPartialMerge() public {
//        // Arrange
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//
//        uint256 initialParentBalance = conditionalTokens.balanceOf(user, parentPositionId);
//        uint256 mergeAmount = AMOUNT / 2;
//        market.wrappedShort().approve(address(market), mergeAmount);
//        market.wrappedLong().approve(address(market), mergeAmount);
//
//        // Act
//        market.merge(mergeAmount);
//
//        // Assert partial balances
//        assertEq(market.wrappedShort().balanceOf(user), AMOUNT - mergeAmount, "Wrong remaining short balance");
//        assertEq(market.wrappedLong().balanceOf(user), AMOUNT - mergeAmount, "Wrong remaining long balance");
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialParentBalance + mergeAmount,
//            "Wrong parent token balance after partial merge"
//        );
//
//        // Arrange
//        market.wrappedShort().approve(address(market), mergeAmount);
//        market.wrappedLong().approve(address(market), mergeAmount);
//
//        // Act
//        market.merge(AMOUNT - mergeAmount);
//
//        // Assert
//        assertEq(market.wrappedShort().balanceOf(user), 0, "Short balance not zero after full merge");
//        assertEq(market.wrappedLong().balanceOf(user), 0, "Long balance not zero after full merge");
//
//        vm.stopPrank();
//    }
//
//    function testRedeem() public {
//        // Arrange //
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        // Resolve condition - Long wins completely.
//        uint256[] memory payoutNumerators = new uint256[](2);
//        payoutNumerators[0] = 0;
//        payoutNumerators[1] = 100;
//        vm.stopPrank();
//
//        // TODO: test that resolve gets its value from oracleAdapter.getAnswer
//        // Resolve condition - Long wins all.
//        bytes32 answer = bytes32(uint256(100e18));
//        vm.mockCall(
//            address(oracleAdapter), abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector), abi.encode(answer)
//        );
//        market.resolve();
//
//        vm.startPrank(user);
//        market.wrappedShort().approve(address(market), AMOUNT);
//        market.wrappedLong().approve(address(market), AMOUNT);
//        uint256 initialDecisionOutcomeBalance = conditionalTokens.balanceOf(user, parentPositionId);
//        // Act //
//        market.redeem(AMOUNT, AMOUNT);
//
//        // Assert //
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialDecisionOutcomeBalance + AMOUNT,
//            "Wrong decision outcome amount"
//        );
//        assertEq(market.wrappedShort().balanceOf(user), 0, "Short tokens not consumed");
//        assertEq(market.wrappedLong().balanceOf(user), 0, "Long tokens not consumed");
//
//        vm.stopPrank();
//    }
//
//    function testRedeemZeroAmount() public {
//        // Arrange //
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        vm.stopPrank();
//
//        // TODO: test that resolve gets its value from oracleAdapter.getAnswer
//        // Resolve condition - 50/50 split
//        bytes32 answer = bytes32(uint256(50e18));
//        vm.mockCall(
//            address(oracleAdapter), abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector), abi.encode(answer)
//        );
//        market.resolve();
//
//        // Try to redeem with some zeros
//        vm.startPrank(user);
//        market.wrappedShort().approve(address(market), AMOUNT);
//        market.wrappedLong().approve(address(market), AMOUNT);
//
//        // Act //
//        // Try to redeem with some zeros
//        uint256 initialCollateral = collateralToken.balanceOf(user);
//        market.redeem(AMOUNT, 0); // Only redeem Short position
//
//        // Assert //
//        // Should get half the amount (50/50 split)
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialCollateral + AMOUNT / 2,
//            "Wrong decision token amount for Short redemption"
//        );
//        assertEq(market.wrappedShort().balanceOf(user), 0, "Short tokens not consumed");
//        assertEq(market.wrappedLong().balanceOf(user), AMOUNT, "Long tokens incorrectly consumed");
//
//        vm.stopPrank();
//    }
//
//    function testRedeemBeforeResolution() public {
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        market.wrappedShort().approve(address(market), AMOUNT);
//        market.wrappedLong().approve(address(market), AMOUNT);
//
//        // Try to redeem before resolution
//        vm.expectRevert("condition not resolved");
//        market.redeem(AMOUNT, AMOUNT);
//        vm.stopPrank();
//    }
//
//    function testRedeemInsufficientShortBalance() public {
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        market.wrappedShort().approve(address(market), type(uint256).max);
//        market.wrappedLong().approve(address(market), type(uint256).max);
//        vm.stopPrank();
//
//        // Resolve condition
//        vm.startPrank(address(market));
//        uint256[] memory payouts = new uint256[](2);
//        payouts[0] = 1;
//        payouts[1] = 1;
//        conditionalTokens.reportPayouts(market.questionId(), payouts);
//        vm.stopPrank();
//
//        vm.startPrank(user);
//        vm.expectRevert(
//            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, AMOUNT, AMOUNT + 1)
//        );
//        market.redeem(AMOUNT + 1, AMOUNT);
//        vm.stopPrank();
//    }
//
//    function testRedeemInsufficientAllowance() public {
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//        vm.stopPrank();
//
//        // Resolve condition
//        vm.startPrank(address(market));
//        uint256[] memory payouts = new uint256[](2);
//        payouts[0] = 1;
//        payouts[1] = 1;
//        conditionalTokens.reportPayouts(market.questionId(), payouts);
//        vm.stopPrank();
//
//        // Approve only Short token
//        vm.startPrank(user);
//        market.wrappedShort().approve(address(market), AMOUNT);
//        // Long token not approved
//
//        vm.expectRevert(
//            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(market), 0, AMOUNT)
//        );
//        market.redeem(AMOUNT, AMOUNT);
//        vm.stopPrank();
//    }
//
//    function testPartialRedeem() public {
//        // First split to get Long/Short tokens
//        vm.startPrank(user);
//        conditionalTokens.setApprovalForAll(address(market), true);
//        market.split(AMOUNT);
//
//        // Resolve condition - 60/40 split
//        uint256[] memory payoutNumerators = new uint256[](2);
//        payoutNumerators[0] = 60; // Short gets 60%
//        payoutNumerators[1] = 40; // Long gets 40%
//        vm.stopPrank();
//
//        vm.startPrank(address(market));
//        conditionalTokens.reportPayouts(market.questionId(), payoutNumerators);
//        vm.stopPrank();
//
//        // Redeem half of each position
//        vm.startPrank(user);
//        market.wrappedShort().approve(address(market), AMOUNT / 2);
//        market.wrappedLong().approve(address(market), AMOUNT / 2);
//
//        uint256 initialCollateral = collateralToken.balanceOf(user);
//        market.redeem(AMOUNT / 2, AMOUNT / 2);
//
//        // Check balances
//        assertEq(
//            conditionalTokens.balanceOf(user, parentPositionId),
//            initialCollateral + AMOUNT / 2, // (60% + 40%) of AMOUNT/2
//            "Wrong collateral amount"
//        );
//        assertEq(market.wrappedShort().balanceOf(user), AMOUNT / 2, "Wrong remaining Short balance");
//        assertEq(market.wrappedLong().balanceOf(user), AMOUNT / 2, "Wrong remaining Long balance");
//
//        vm.stopPrank();
//    }
//
//    function _generateBasicPartition(uint256 outcomeSlotCount) private pure returns (uint256[] memory) {
//        uint256[] memory partition = new uint256[](outcomeSlotCount);
//        for (uint256 i = 0; i < outcomeSlotCount; i++) {
//            partition[i] = 1 << i;
//        }
//        return partition;
//    }
//}
//
//contract ResolveTest is Test {
//    ConditionalScalarMarket market;
//    ConditionalTokens conditionalTokens;
//    Wrapped1155Factory wrapped1155Factory;
//    FlatCFMRealityAdapter oracleAdapter;
//    TestToken collateralToken;
//    FakeRealityETH realityETH;
//
//    address arbitrator = address(2);
//    bytes32 constant PARENT_QUESTION_ID = bytes32(uint256(4242123123));
//    bytes32 conditionId;
//
//    function setUp() public {
//        collateralToken = new TestToken();
//        realityETH = new FakeRealityETH();
//        conditionalTokens = new ConditionalTokens();
//        wrapped1155Factory = new Wrapped1155Factory();
//        oracleAdapter =
//            new FlatCFMRealityAdapter(IRealityETH(address(realityETH)), arbitrator, 2, 1, uint32(7 days), 1e18);
//
//        // Prepare parent condition
//        conditionalTokens.prepareCondition(address(oracleAdapter), PARENT_QUESTION_ID, 2);
//        bytes32 parentConditionId = conditionalTokens.getConditionId(address(oracleAdapter), PARENT_QUESTION_ID, 2);
//
//        ScalarQuestionParams memory scalarQuestionParams = ScalarQuestionParams({
//            metricName: "Market Cap",
//            startDate: "2024-01-01",
//            endDate: "2024-12-31",
//            minValue: 0,
//            maxValue: 100e18,
//            openingTime: uint32(block.timestamp + 1 days)
//        });
//
//        ConditionalTokensParams memory ctParams = ConditionalTokensParams({
//            parentConditionId: parentConditionId,
//            outcomeName: "Market Cap Q1",
//            outcomeIndex: 0,
//            collateralToken: IERC20(address(collateralToken))
//        });
//
//        market = new ConditionalScalarMarket(
//            oracleAdapter,
//            IConditionalTokens(address(conditionalTokens)),
//            IWrapped1155Factory(address(wrapped1155Factory)),
//            scalarQuestionParams,
//            ctParams
//        );
//
//        conditionId = market.conditionId();
//    }
//
//    function testResolveBelowMin() public {
//        resolveAndVerify(bytes32(uint256(0)), 1, 0); // Full short payout
//    }
//
//    function testResolveAboveMax() public {
//        resolveAndVerify(bytes32(uint256(150e18)), 0, 1); // Full long payout
//    }
//
//    function testResolveMidPoint() public {
//        resolveAndVerify(bytes32(uint256(50e18)), 50e18, 50e18); // 50-50 split
//    }
//
//    function testResolveInvalid() public {
//        // TODO: rather mock isInvalid and test FlatCFMRealityAdapter independently
//        bytes32 answer = bytes32(type(uint256).max);
//        vm.mockCall(
//            address(realityETH),
//            abi.encodeWithSelector(FakeRealityETH.resultForOnceSettled.selector),
//            abi.encode(answer)
//        );
//
//        market.resolve();
//        assertEq(conditionalTokens.payoutNumerators(conditionId, 0), 1);
//        assertEq(conditionalTokens.payoutNumerators(conditionId, 1), 1);
//    }
//
//    function resolveAndVerify(bytes32 answer, uint256 expectedShortPayout, uint256 expectedLongPayout) internal {
//        vm.mockCall(
//            address(realityETH),
//            abi.encodeWithSelector(FakeRealityETH.resultForOnceSettled.selector),
//            abi.encode(answer)
//        );
//
//        market.resolve();
//
//        assertEq(conditionalTokens.payoutNumerators(conditionId, 0), expectedShortPayout);
//        assertEq(conditionalTokens.payoutNumerators(conditionId, 1), expectedLongPayout);
//    }
//}
