// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "../src/ConditionalTokens.sol";
import "../src/FPMMDeterministicFactory.sol";
import "../src/Wrapped1155Factory.sol";
import "../src/butter-v1/DecisionMarketFactory.sol";
import "../src/butter-v1/CFMRealityAdapter.sol";
import "../src/FixedProductMarketMaker.sol";
import "./FakeRealityETH.sol";

contract CollateralToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Collateral Token", "CLT") {
        _mint(msg.sender, initialSupply);
    }
}

// XXX add names to addresses
contract BaseIntegratedTest is Test {
    ConditionalTokens public conditionalTokens;
    Wrapped1155Factory public wrapped1155Factory;
    DecisionMarketFactory public decisionMarketFactory;
    ICFMOracleAdapter public oracleAdapter;
    CollateralToken public collateralToken;
    FakeRealityETH public fakeRealityEth;
    FPMMDeterministicFactory public fpmmFactory;

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

        fpmmFactory = new FPMMDeterministicFactory();
        vm.label(address(fpmmFactory), "FPMMFactory");

        collateralToken.transfer(USER, USER_SUPPLY);
    }

    function testDependenciesDeployments() public view {
        assertTrue(address(collateralToken) != address(0));
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(fakeRealityEth) != address(0));
    }

    function deployMarketMaker(bytes32[] calldata conditionIds) public returns (FixedProductMarketMaker) {
        return FixedProductMarketMaker(
            fpmmFactory.create2FixedProductMarketMaker(
                1,
                conditionalTokens,
                collateralToken,
                conditionIds,
                0, // fee
                INITIAL_LIQUIDITY, // Set initial funds to INITIAL_LIQUIDITY
                new uint256[](0) // empty distribution hint
            )
        );
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
        decisionMarketFactory = new DecisionMarketFactory(oracleAdapter, conditionalTokens, wrapped1155Factory);
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

contract SplitTest is CreateConditionalMarketsTest {
    uint256 constant DECISION_SPLIT_AMOUNT = USER_SUPPLY / 10;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);

        collateralToken.approve(address(conditionalTokens), DECISION_SPLIT_AMOUNT);
        // This would be prepared by the front-end.
        uint256[] memory partition = new uint256[](decisionMarket.outcomeCount());
        for (uint256 i = 0; i < decisionMarket.outcomeCount(); i++) {
            partition[i] = 1 << i;
        }
        conditionalTokens.splitPosition(
            collateralToken,
            bytes32(0), // No parent
            decisionMarket.conditionId(),
            partition,
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

//// TODO: test trading on the FPMM
//contract TradeTest is SplitTest {}
//
//// TODO: test merging some back
//contract MergeTest is TradeTest {}
//
//// TODO: Resolve decision market
//contract ResolveDecisionTest is MergeTest {}
//
//// TODO: Split, trade, merge some more
//contract TradeAfterDecisionTest is ResolveDecisionTest {}
//
//// TODO: Resolve conditional markets
//contract ResolveConditionalsTest is TradeAfterDecisionTest {}
//
//// TODO: Redeem
//contract RedeemTest is ResolveConditionalsTest {}
