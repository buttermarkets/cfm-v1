// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable no-console
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol";
import {Arbitrator} from "@realityeth/packages/contracts/flat/Arbitrator-development.sol";
import {IRealityETH} from "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";

import "src/invalidless/InvalidlessConditionalScalarMarketFactory.sol";
import "src/invalidless/InvalidlessConditionalScalarMarket.sol";
import "src/FlatCFMRealityAdapter.sol";
import {ScalarParams, GenericScalarQuestionParams} from "src/Types.sol";

import "../vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "../vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "../fake/SimpleAMM.sol";

contract CollateralToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Collateral Token", "CLT") {
        _mint(msg.sender, initialSupply);
    }
}

contract Base is Test {
    ConditionalTokens public conditionalTokens;
    Wrapped1155Factory public wrapped1155Factory;
    RealityETH_v3_0 public reality;
    Arbitrator public arbitrator;
    CollateralToken public collateralToken;

    address USER = makeAddr("USER");

    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant USER_SUPPLY = 5000 ether;
    uint256 public constant INITIAL_LIQUIDITY = 1000 ether;
    uint32 public constant QUESTION_TIMEOUT = 86_400;
    uint256 public constant MIN_BOND = 100;

    function setUp() public virtual {
        vm.label(USER, "User");

        conditionalTokens = new ConditionalTokens();
        vm.label(address(conditionalTokens), "ConditionalTokens");
        wrapped1155Factory = new Wrapped1155Factory();
        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
        reality = new RealityETH_v3_0();
        vm.label(address(reality), "RealityETH");
        arbitrator = new Arbitrator();
        arbitrator.setRealitio(address(reality));
        vm.label(address(arbitrator), "Arbitrator");
        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");
        collateralToken.transfer(USER, USER_SUPPLY);
    }

    function _getDiscreetPartition() internal pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1; // short
        partition[1] = 2; // long
        return partition;
    }
}

contract DependenciesTest is Base {
    function testDependenciesDeployments() public view {
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(reality) != address(0));
    }
}

contract DeployCoreContractsBase is Base {
    FlatCFMOracleAdapter public oracleAdapter;
    InvalidlessConditionalScalarMarketFactory public factory;

    function setUp() public virtual override {
        super.setUp();
        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(arbitrator), QUESTION_TIMEOUT, MIN_BOND);
        factory = new InvalidlessConditionalScalarMarketFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );
    }
}

contract DeployCoreContractsTest is DeployCoreContractsBase {
    function testMarketFactoryDeployment() public view {
        assertTrue(address(factory) != address(0));
    }

    function testOracleAdapterDeployment() public view {
        assertTrue(address(oracleAdapter) != address(0));
    }
}

contract CreateMarketBase is DeployCoreContractsBase {
    GenericScalarQuestionParams genericScalarQuestionParams;
    uint256 metricTemplateId;
    InvalidlessConditionalScalarMarket icsm;
    bytes32 icsmConditionId;
    bytes32 icsmQuestionId;
    string constant OUTCOME_NAME = "BTC Price";
    uint256[2] defaultInvalidPayouts = [uint256(1), uint256(1)];

    function setUp() public virtual override {
        super.setUp();

        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 20_000, maxValue: 100_000}),
            openingTime: uint32(block.timestamp + 90 days)
        });

        metricTemplateId = reality.createTemplate(
            '{\"title\": \"What is the price of %s in USD?\", \"type\": \"uint\", \"category\": \"crypto-price\", \"lang\": \"en\"}'
        );

        vm.recordLogs();
        icsm = factory.createInvalidlessConditionalScalarMarket(
            oracleAdapter,
            metricTemplateId,
            OUTCOME_NAME,
            genericScalarQuestionParams,
            defaultInvalidPayouts,
            collateralToken
        );
        _recordQuestionAndConditionId();

        vm.label(address(icsm), "ICSM");
    }

    function _recordQuestionAndConditionId() internal {
        // Get questionId and conditionId from the icsm contract
        (bytes32 questionId, bytes32 conditionId,,) = icsm.ctParams();
        icsmQuestionId = questionId;
        icsmConditionId = conditionId;
        
        assertTrue(icsmQuestionId != bytes32(0), "questionId not found");
        assertTrue(icsmConditionId != bytes32(0), "conditionId not found");
    }
}

contract CreateMarketTest is CreateMarketBase {
    function testMarketCreated() public view {
        assertTrue(address(icsm) != address(0));
    }

    function testQuestionIdSet() public view {
        assertTrue(icsmQuestionId != bytes32(0), "questionId not found");
    }

    function testConditionIdSet() public view {
        assertTrue(icsmConditionId != bytes32(0), "conditionId not found");
    }

    function testMarketParameters() public view {
        (uint256 minValue, uint256 maxValue) = icsm.scalarParams();
        assertEq(minValue, 20_000);
        assertEq(maxValue, 100_000);
        assertEq(icsm.defaultInvalidPayouts(0), defaultInvalidPayouts[0]);
        assertEq(icsm.defaultInvalidPayouts(1), defaultInvalidPayouts[1]);
    }
}

contract SplitPositionTestBase is CreateMarketBase {
    uint256 constant SPLIT_AMOUNT = USER_SUPPLY / 10;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);
        collateralToken.approve(address(conditionalTokens), SPLIT_AMOUNT);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), icsmConditionId, _getDiscreetPartition(), SPLIT_AMOUNT
        );
        vm.stopPrank();
    }
}

contract SplitPositionTest is SplitPositionTestBase {
    function testSplitPositionBalance() public view {
        (,, bytes32 parentCollectionId,) = icsm.ctParams();
        assertEq(parentCollectionId, bytes32(0), "parent collection ID should be zero for standalone market");
        
        // Check that user has both short and long positions
        uint256 shortPositionId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), icsmConditionId, 1)
        );
        uint256 longPositionId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), icsmConditionId, 2)
        );
        
        assertEq(conditionalTokens.balanceOf(USER, shortPositionId), SPLIT_AMOUNT);
        assertEq(conditionalTokens.balanceOf(USER, longPositionId), SPLIT_AMOUNT);
    }
}

contract WrapTokensTestBase is SplitPositionTestBase {
    IERC20 wrappedShort;
    IERC20 wrappedLong;
    uint256 shortPositionId;
    uint256 longPositionId;
    bytes shortData;
    bytes longData;

    function setUp() public virtual override {
        super.setUp();
        
        // Get wrapped token data
        (shortData, longData, shortPositionId, longPositionId, wrappedShort, wrappedLong) = icsm.wrappedCTData();

        vm.startPrank(USER);
        
        // Transfer positions to wrapper factory to wrap them
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), shortPositionId, SPLIT_AMOUNT, shortData
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), longPositionId, SPLIT_AMOUNT, longData
        );
        
        vm.stopPrank();
    }
}

contract WrapTokensTest is WrapTokensTestBase {
    function testWrappedTokenBalances() public view {
        assertEq(wrappedShort.balanceOf(USER), SPLIT_AMOUNT);
        assertEq(wrappedLong.balanceOf(USER), SPLIT_AMOUNT);
        assertEq(conditionalTokens.balanceOf(USER, shortPositionId), 0);
        assertEq(conditionalTokens.balanceOf(USER, longPositionId), 0);
    }
}

contract TradeTestBase is WrapTokensTestBase, ERC1155Holder {
    uint256 constant TRADE_AMOUNT = SPLIT_AMOUNT / 4;
    uint256 constant CONTRACT_LIQUIDITY = INITIAL_SUPPLY / 100;
    SimpleAMM public amm;

    function setUp() public virtual override {
        super.setUp();

        // Get contract's initial positions for liquidity
        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), icsmConditionId, _getDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        // Wrap contract's positions
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), shortPositionId, CONTRACT_LIQUIDITY, shortData
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), longPositionId, CONTRACT_LIQUIDITY, longData
        );

        // Create AMM
        amm = new SimpleAMM(wrappedShort, wrappedLong);
        vm.label(address(amm), "AMM");

        // Add liquidity
        wrappedShort.approve(address(amm), CONTRACT_LIQUIDITY);
        wrappedLong.approve(address(amm), CONTRACT_LIQUIDITY);
        amm.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        // User trades short for long
        vm.startPrank(USER);
        wrappedShort.approve(address(amm), TRADE_AMOUNT);
        amm.swap(true, TRADE_AMOUNT);
        vm.stopPrank();
    }
}

contract TradeTest is TradeTestBase {
    function testTradeOutcome() public view {
        assertTrue(wrappedShort.balanceOf(USER) < SPLIT_AMOUNT);
        assertTrue(wrappedLong.balanceOf(USER) > SPLIT_AMOUNT);
        assertTrue(wrappedShort.balanceOf(address(amm)) > CONTRACT_LIQUIDITY);
        assertTrue(wrappedLong.balanceOf(address(amm)) < CONTRACT_LIQUIDITY);
        console.log("Tested trade outcome");
    }
}

contract MergeTestBase is TradeTestBase {
    uint256 constant MERGE_AMOUNT = TRADE_AMOUNT;
    uint256 userShortBeforeMerge;
    uint256 userLongBeforeMerge;

    function setUp() public virtual override {
        super.setUp();

        userShortBeforeMerge = wrappedShort.balanceOf(USER);
        userLongBeforeMerge = wrappedLong.balanceOf(USER);

        vm.startPrank(USER);

        // Unwrap tokens first
        wrappedShort.approve(address(wrapped1155Factory), MERGE_AMOUNT);
        wrappedLong.approve(address(wrapped1155Factory), MERGE_AMOUNT);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionId, MERGE_AMOUNT, USER, shortData);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionId, MERGE_AMOUNT, USER, longData);

        // Merge positions
        conditionalTokens.mergePositions(
            collateralToken, bytes32(0), icsmConditionId, _getDiscreetPartition(), MERGE_AMOUNT
        );

        vm.stopPrank();
    }
}

contract MergeTest is MergeTestBase {
    function testMergePositions() public view {
        console.log("Testing merge positions");
        assertEq(wrappedShort.balanceOf(USER), userShortBeforeMerge - MERGE_AMOUNT);
        assertEq(wrappedLong.balanceOf(USER), userLongBeforeMerge - MERGE_AMOUNT);
        assertEq(collateralToken.balanceOf(USER), USER_SUPPLY - SPLIT_AMOUNT + MERGE_AMOUNT);
    }
}

contract BadAnswerSubmitTest is MergeTestBase {
    address ANSWERER = makeAddr("answerer");

    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
    }

    function testCantResolveIfUnresolved() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            icsmQuestionId, 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question was settled too soon and has not been reopened");
        icsm.resolve();
    }

    function testCanResolveIfInvalid() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            icsmQuestionId, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        icsm.resolve();

        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 0), defaultInvalidPayouts[0]);
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 1), defaultInvalidPayouts[1]);
    }

    function testCanResolveIfTooHigh() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            icsmQuestionId, bytes32(uint256(genericScalarQuestionParams.scalarParams.maxValue + 1)), 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        icsm.resolve();

        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 1), 1);
    }

    function testCanResolveIfTooLow() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            icsmQuestionId, bytes32(uint256(genericScalarQuestionParams.scalarParams.minValue - 1)), 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        icsm.resolve();

        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 0), 1);
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 1), 0);
    }
}

contract GoodAnswerSubmitTestBase is MergeTestBase {
    address ANSWERER = makeAddr("answerer");
    uint256 constant ANSWER_VALUE = 60_000; // Mid-range answer

    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(icsmQuestionId, bytes32(ANSWER_VALUE), 0);
    }
}

contract GoodAnswerSubmitTest is GoodAnswerSubmitTestBase {
    address CHALLENGER = makeAddr("challenger");

    function testCantResolveBeforeTimeout() public {
        vm.expectRevert("question must be finalized");
        icsm.resolve();
    }

    function testCantResolveAfterTimeoutIfChallenged() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);

        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(icsmQuestionId, bytes32(uint256(50_000)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("question must be finalized");
        icsm.resolve();
    }

    function testCanResolveAfterChallengeTimeout() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);
        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(icsmQuestionId, bytes32(uint256(40_000)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1 + QUESTION_TIMEOUT);
        icsm.resolve();

        // With answer 40,000 in range [20,000, 100,000]:
        // Short payout = (100,000 - 40,000) / (100,000 - 20,000) = 60,000 / 80,000 = 0.75
        // Long payout = (40,000 - 20,000) / (100,000 - 20,000) = 20,000 / 80,000 = 0.25
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 0), 60_000);
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 1), 20_000);
    }
}

contract MarketResolveTestBase is GoodAnswerSubmitTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        icsm.resolve();
    }
}

contract MarketResolveTest is MarketResolveTestBase {
    function testReportedPayouts() public view {
        // With answer 60,000 in range [20,000, 100,000]:
        // Short payout = (100,000 - 60,000) / (100,000 - 20,000) = 40,000 / 80,000 = 0.5
        // Long payout = (60,000 - 20,000) / (100,000 - 20,000) = 40,000 / 80,000 = 0.5
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 0), 40_000);
        assertEq(conditionalTokens.payoutNumerators(icsmConditionId, 1), 40_000);
    }
}

contract RedeemTestBase is MarketResolveTestBase {
    uint256 prevUserShort;
    uint256 prevUserLong;
    uint256 prevUserCollateral;

    function setUp() public virtual override {
        super.setUp();

        prevUserShort = wrappedShort.balanceOf(USER);
        prevUserLong = wrappedLong.balanceOf(USER);
        prevUserCollateral = collateralToken.balanceOf(USER);

        vm.startPrank(USER);

        // Unwrap all remaining tokens
        uint256 shortAmount = prevUserShort;
        uint256 longAmount = prevUserLong;

        wrappedShort.approve(address(wrapped1155Factory), shortAmount);
        wrappedLong.approve(address(wrapped1155Factory), longAmount);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionId, shortAmount, USER, shortData);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionId, longAmount, USER, longData);

        // Redeem positions
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), icsmConditionId, _getDiscreetPartition());

        vm.stopPrank();
    }
}

contract RedeemTest is RedeemTestBase {
    function testRedeemUpdatesBalances() public view {
        console.log("Testing redeem updates balances");
        
        // All wrapped tokens should be unwrapped
        assertEq(wrappedShort.balanceOf(USER), 0);
        assertEq(wrappedLong.balanceOf(USER), 0);
        
        // With 50/50 payout, user should get back the full amount
        uint256 expectedPayout = (prevUserShort + prevUserLong) / 2;
        assertEq(collateralToken.balanceOf(USER), prevUserCollateral + expectedPayout);
    }
}

contract FullCycleTest is RedeemTestBase {
    function testFullCycle() public view {
        console.log("Testing full cycle");
        
        // User started with USER_SUPPLY
        // Split SPLIT_AMOUNT
        // Merged MERGE_AMOUNT back
        // Redeemed remaining positions at 50/50 payout
        
        uint256 remainingPositions = SPLIT_AMOUNT - MERGE_AMOUNT;
        uint256 expectedCollateral = USER_SUPPLY - SPLIT_AMOUNT + MERGE_AMOUNT + remainingPositions;
        
        assertEq(collateralToken.balanceOf(USER), expectedCollateral);
        console.log("User started with:", USER_SUPPLY);
        console.log("User ended with:", collateralToken.balanceOf(USER));
    }
}