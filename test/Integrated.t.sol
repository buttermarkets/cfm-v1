// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "src/vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "src/vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "src/DecisionMarketFactory.sol";
import "src/CFMRealityAdapter.sol";
import "./FakeRealityETH.sol";
import "./SimpleAMM.sol";

contract CollateralToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Collateral Token", "CLT") {
        _mint(msg.sender, initialSupply);
    }
}

contract BaseIntegratedTest is Test {
    ConditionalTokens public conditionalTokens;
    Wrapped1155Factory public wrapped1155Factory;
    DecisionMarketFactory public decisionMarketFactory;
    ICFMOracleAdapter public oracleAdapter;
    CollateralToken public collateralToken;
    FakeRealityETH public fakeRealityEth;

    address USER = address(1);
    address DUMMY_ARBITRATOR = address(0x42424242);

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;
    uint256 public constant USER_SUPPLY = 5000 * 10 ** 18;
    uint256 public constant INITIAL_LIQUIDITY = 1000 * 10 ** 18;
    uint32 public constant QUESTION_TIMEOUT = 86400; // 24 hours
    uint256 public constant MIN_BOND = 100;

    function setUp() public virtual {
        vm.label(USER, "User");
        vm.label(DUMMY_ARBITRATOR, "Arbitrator");

        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");
        conditionalTokens = new ConditionalTokens();
        vm.label(address(conditionalTokens), "ConditionalTokens");
        wrapped1155Factory = new Wrapped1155Factory();
        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
        fakeRealityEth = new FakeRealityETH();
        vm.label(address(fakeRealityEth), "RealityETH");

        collateralToken.transfer(USER, USER_SUPPLY);
    }

    function testDependenciesDeployments() public view {
        assertTrue(address(collateralToken) != address(0));
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(fakeRealityEth) != address(0));
    }
}

contract DeployCoreContractsTest is BaseIntegratedTest {
    function setUp() public virtual override {
        super.setUp();

        oracleAdapter = new CFMRealityAdapter(
            IRealityETH(address(fakeRealityEth)),
            DUMMY_ARBITRATOR,
            2, // templateId for categorical
            1, // templateId for scalar
            QUESTION_TIMEOUT,
            MIN_BOND
        );
        decisionMarketFactory = new DecisionMarketFactory(
            oracleAdapter,
            IConditionalTokens(address(conditionalTokens)),
            IWrapped1155Factory(address(wrapped1155Factory))
        );
    }

    function testDecisionMarketFactoryDeployment() public view {
        assertTrue(address(decisionMarketFactory) != address(0));
    }

    function testOracleAdapterDeployment() public view {
        assertTrue(address(oracleAdapter) != address(0));
    }
}

contract CreateDecisionMarketTest is DeployCoreContractsTest {
    CFMDecisionQuestionParams decisionQuestionParams;
    CFMConditionalQuestionParams conditionalQuestionParams;

    function setUp() public virtual override {
        super.setUp();

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Project A";
        outcomes[1] = "Project B";
        outcomes[2] = "Project C";

        decisionQuestionParams = CFMDecisionQuestionParams({
            roundName: "Which project will get funded?",
            outcomeNames: outcomes,
            openingTime: uint32(block.timestamp + 2 * 24 * 3600)
        });

        conditionalQuestionParams = CFMConditionalQuestionParams({
            metricName: "ETH Price",
            startDate: "2024-01-01",
            endDate: "2024-12-31",
            minValue: 0,
            maxValue: 10000,
            openingTime: uint32(block.timestamp + 90 * 24 * 3600)
        });

        // Create market
        decisionMarketFactory.createMarket(decisionQuestionParams, conditionalQuestionParams, collateralToken);
    }

    function testMarketsCountUp() public view {
        assertEq(decisionMarketFactory.marketCount(), 1);
    }

    function testDecisionMarketCreated() public view {
        CFMDecisionMarket decisionMarket =
            CFMDecisionMarket(decisionMarketFactory.markets(decisionMarketFactory.marketCount() - 1));
        assertTrue(address(decisionMarket) != address(0));
    }
}

contract CreateConditionalMarketsTest is CreateDecisionMarketTest {
    CFMDecisionMarket decisionMarket;
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;

    function setUp() public virtual override {
        super.setUp();

        decisionMarket = CFMDecisionMarket(decisionMarketFactory.markets(decisionMarketFactory.marketCount() - 1));
        vm.label(address(decisionMarket), "DecisionMarket");
        conditionalMarketA = decisionMarket.outcomes(0);
        vm.label(address(decisionMarket.outcomes(0)), "ConditionalMarketA");
        conditionalMarketB = decisionMarket.outcomes(1);
        vm.label(address(decisionMarket.outcomes(1)), "ConditionalMarketB");
        conditionalMarketC = decisionMarket.outcomes(2);
        vm.label(address(decisionMarket.outcomes(2)), "ConditionalMarketC");
    }

    function testOutcomeCount() public view {
        assertEq(decisionMarket.outcomeCount(), 3);
    }

    function testConditionalMarketsCreated() public view {
        assertTrue(address(decisionMarket.outcomes(0)) != address(0));
        assertTrue(address(decisionMarket.outcomes(1)) != address(0));
        assertTrue(address(decisionMarket.outcomes(2)) != address(0));
    }
}

contract SplitTestBase is CreateConditionalMarketsTest {
    uint256 constant DECISION_SPLIT_AMOUNT = USER_SUPPLY / 10;

    function decisionDiscreetPartition() public view returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](decisionMarket.outcomeCount());
        for (uint256 i = 0; i < decisionMarket.outcomeCount(); i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);

        collateralToken.approve(address(conditionalTokens), DECISION_SPLIT_AMOUNT);

        // This would be prepared by the front-end.
        conditionalTokens.splitPosition(
            collateralToken,
            bytes32(0), // No parent
            decisionMarket.conditionId(),
            decisionDiscreetPartition(),
            DECISION_SPLIT_AMOUNT
        );

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        // Do some splits:
        conditionalMarketA.split(DECISION_SPLIT_AMOUNT);
        conditionalMarketB.split(DECISION_SPLIT_AMOUNT / 2);

        vm.stopPrank();
    }
}

contract SplitTest is SplitTestBase {
    function testSplitPositionA() public view {
        assertEq(conditionalMarketA.wrappedShort().balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(conditionalMarketA.wrappedLong().balanceOf(USER), DECISION_SPLIT_AMOUNT);
    }

    function testSplitPositionB() public view {
        assertEq(conditionalMarketB.wrappedShort().balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(conditionalMarketB.wrappedLong().balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
    }

    function testSplitPositionC() public view {
        assertEq(conditionalMarketC.wrappedShort().balanceOf(USER), 0);
        assertEq(conditionalMarketC.wrappedLong().balanceOf(USER), 0);
    }
}

contract TradeTest is SplitTestBase, ERC1155Holder {
    uint256 constant TRADE_AMOUNT = DECISION_SPLIT_AMOUNT / 4;
    uint256 constant CONTRACT_LIQUIDITY = INITIAL_SUPPLY / 100; // Use 1% of initial supply for AMM liquidity
    SimpleAMM public ammA;
    SimpleAMM public ammB;

    function setUp() public virtual override {
        super.setUp();

        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);

        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), decisionMarket.conditionId(), decisionDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        // Split decision tokens into Long/Short pairs
        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalMarketA.split(CONTRACT_LIQUIDITY);
        conditionalMarketB.split(CONTRACT_LIQUIDITY);

        // Create and initialize AMMs
        ammA = new SimpleAMM(conditionalMarketA.wrappedShort(), conditionalMarketA.wrappedLong());
        ammB = new SimpleAMM(conditionalMarketB.wrappedShort(), conditionalMarketB.wrappedLong());

        // Contract provides liquidity
        conditionalMarketA.wrappedShort().approve(address(ammA), CONTRACT_LIQUIDITY);
        conditionalMarketA.wrappedLong().approve(address(ammA), CONTRACT_LIQUIDITY);
        conditionalMarketB.wrappedShort().approve(address(ammB), CONTRACT_LIQUIDITY);
        conditionalMarketB.wrappedLong().approve(address(ammB), CONTRACT_LIQUIDITY);

        ammA.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);
        ammB.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        // User trades
        vm.startPrank(USER);

        // Market A: User trades short for long, taking a long position
        conditionalMarketA.wrappedShort().approve(address(ammA), TRADE_AMOUNT);
        ammA.swap(true, TRADE_AMOUNT);

        // Market B: User trades more short for long, taking a larger long position
        conditionalMarketB.wrappedShort().approve(address(ammB), TRADE_AMOUNT * 2);
        ammB.swap(true, TRADE_AMOUNT * 2);

        vm.stopPrank();
    }

    function testTradeOutcomeA() public view {
        // User should have less short and more long tokens in market A
        assertTrue(conditionalMarketA.wrappedShort().balanceOf(USER) < DECISION_SPLIT_AMOUNT);
        assertTrue(conditionalMarketA.wrappedLong().balanceOf(USER) > DECISION_SPLIT_AMOUNT);
        // AMM should reflect this
        assertTrue(ammA.reserve0() > CONTRACT_LIQUIDITY); // More short tokens in pool
        assertTrue(ammA.reserve1() < CONTRACT_LIQUIDITY); // Less long tokens in pool
    }

    //function testTradeOutcomeB() public view {
    //    // User should have even less short and even more long tokens in market B
    //    assertTrue(
    //        conditionalMarketB.wrappedShort().balanceOf(USER) < conditionalMarketA.wrappedShort().balanceOf(USER),
    //        "wrappedShort comparision error"
    //    );
    //    assertTrue(
    //        conditionalMarketB.wrappedLong().balanceOf(USER) > conditionalMarketA.wrappedLong().balanceOf(USER),
    //        "wrappedLong comparison error"
    //    );
    //    // AMM should reflect larger imbalance
    //    assertTrue(ammB.reserve0() > ammA.reserve0()); // Even more short tokens in pool
    //    assertTrue(ammB.reserve1() < ammA.reserve1()); // Even less long tokens in pool
    //}
}

//contract MergeTest is TradeTest {
//    uint256 constant MERGE_AMOUNT = DECISION_SPLIT_AMOUNT / 5;
//
//    function setUp() public virtual override {
//        super.setUp();
//
//        vm.startPrank(USER);
//
//        conditionalMarketA.wrappedLong().approve(address(conditionalMarketA), MERGE_AMOUNT);
//        conditionalMarketA.wrappedShort().approve(address(conditionalMarketA), MERGE_AMOUNT);
//        conditionalMarketB.wrappedLong().approve(address(conditionalMarketB), MERGE_AMOUNT);
//        conditionalMarketB.wrappedShort().approve(address(conditionalMarketB), MERGE_AMOUNT);
//
//        conditionalMarketA.merge(MERGE_AMOUNT);
//        conditionalMarketB.merge(MERGE_AMOUNT);
//
//        vm.stopPrank();
//    }
//
//    function testMergePositionsA() public view {
//        assertEq(conditionalMarketA.wrappedLong().balanceOf(USER), conditionalMarketA.wrappedShort().balanceOf(USER));
//    }
//
//    function testMergePositionsB() public view {
//        assertEq(conditionalMarketB.wrappedLong().balanceOf(USER), conditionalMarketB.wrappedShort().balanceOf(USER));
//    }
//}

//contract ResolveDecisionTest is MergeTest {}
//
//contract TradeAfterDecisionTest is ResolveDecisionTest {}
//
//contract ResolveConditionalsTest is TradeAfterDecisionTest {}
//
//contract RedeemTest is ResolveConditionalsTest {}
