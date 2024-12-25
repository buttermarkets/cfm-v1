// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "src/vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "src/vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "src/FlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";
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
    CollateralToken public collateralToken;
    FakeRealityETH public fakeRealityEth;

    address USER = address(1);
    address DUMMY_ARBITRATOR = address(0x42424242);

    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;
    uint256 public constant USER_SUPPLY = 5000 * 10 ** 18;
    uint256 public constant INITIAL_LIQUIDITY = 1000 * 10 ** 18;
    uint32 public constant QUESTION_TIMEOUT = 86400;
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
}

contract BaseIntegratedTestCheck is BaseIntegratedTest {
    function testDependenciesDeployments() public view {
        assertTrue(address(collateralToken) != address(0));
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(fakeRealityEth) != address(0));
    }
}

contract DeployCoreContractsBase is BaseIntegratedTest {
    FlatCFMOracleAdapter public oracleAdapter;
    FlatCFMFactory public decisionMarketFactory;

    function setUp() public virtual override {
        super.setUp();
        oracleAdapter = new FlatCFMRealityAdapter(
            IRealityETH(address(fakeRealityEth)), DUMMY_ARBITRATOR, 2, 1, QUESTION_TIMEOUT, MIN_BOND
        );
        decisionMarketFactory = new FlatCFMFactory(
            oracleAdapter,
            IConditionalTokens(address(conditionalTokens)),
            IWrapped1155Factory(address(wrapped1155Factory))
        );
    }
}

contract DeployCoreContractsTest is DeployCoreContractsBase {
    function testDecisionMarketFactoryDeployment() public view {
        assertTrue(address(decisionMarketFactory) != address(0));
    }

    function testOracleAdapterDeployment() public view {
        assertTrue(address(oracleAdapter) != address(0));
    }
}

contract CreateDecisionMarketBase is DeployCoreContractsBase {
    FlatCFMQuestionParams cfmQuestionParams;
    ScalarQuestionParams scalarQuestionParams;
    FlatCFM cfm;
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;

    function setUp() public virtual override {
        super.setUp();

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Project A";
        outcomes[1] = "Project B";
        outcomes[2] = "Project C";

        cfmQuestionParams = FlatCFMQuestionParams({
            roundName: "Which project will get funded?",
            outcomeNames: outcomes,
            openingTime: uint32(block.timestamp + 2 * 24 * 3600)
        });

        scalarQuestionParams = ScalarQuestionParams({
            metricName: "ETH Price",
            startDate: "2024-01-01",
            endDate: "2024-12-31",
            minValue: 0,
            maxValue: 10000,
            openingTime: uint32(block.timestamp + 90 * 24 * 3600)
        });

        vm.recordLogs();
        cfm = decisionMarketFactory.createMarket(cfmQuestionParams, scalarQuestionParams, collateralToken);
        recordScalarMarkets();
        vm.label(address(cfm), "DecisionMarket");
        vm.label(address(conditionalMarketA), "ConditionalMarketA");
        vm.label(address(conditionalMarketB), "ConditionalMarketB");
        vm.label(address(conditionalMarketC), "ConditionalMarketC");
    }

    function recordScalarMarkets() public {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("ConditionalMarketCreated(address,address,uint256,address)");

        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)) {
                if (found == 0) {
                    conditionalMarketA = ConditionalScalarMarket(address(uint160(uint256(logs[i].topics[2]))));
                }
                if (found == 1) {
                    conditionalMarketB = ConditionalScalarMarket(address(uint160(uint256(logs[i].topics[2]))));
                }
                if (found == 2) {
                    conditionalMarketC = ConditionalScalarMarket(address(uint160(uint256(logs[i].topics[2]))));
                }
                found++;
            }
        }
        assertTrue(address(conditionalMarketA) != address(0), "Conditional market not found");
    }
}

contract CreateDecisionMarketTest is CreateDecisionMarketBase {
    function testDecisionMarketCreated() public view {
        assertTrue(address(cfm) != address(0));
    }
}

contract CreateConditionalMarketsTest is CreateDecisionMarketBase {
    function testOutcomeCount() public view {
        assertEq(cfm.outcomeCount(), 3);
    }
}

contract SplitTestBase is CreateDecisionMarketBase {
    uint256 constant DECISION_SPLIT_AMOUNT = USER_SUPPLY / 10;
    uint256 constant DECISION_SPLIT_AMOUNT_A = DECISION_SPLIT_AMOUNT;
    uint256 constant DECISION_SPLIT_AMOUNT_B = DECISION_SPLIT_AMOUNT / 2;

    function decisionDiscreetPartition() public view returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](cfm.outcomeCount());
        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);

        collateralToken.approve(address(conditionalTokens), DECISION_SPLIT_AMOUNT);

        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfm.conditionId(), decisionDiscreetPartition(), DECISION_SPLIT_AMOUNT
        );

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(DECISION_SPLIT_AMOUNT_A);
        conditionalMarketB.split(DECISION_SPLIT_AMOUNT_B);

        vm.stopPrank();
    }
}

contract SplitTest is SplitTestBase {
    function testSplitPositionA() public view {
        assertEq(conditionalMarketA.wrappedShort().balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(conditionalMarketA.wrappedLong().balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(userBalanceOutcomeA(), DECISION_SPLIT_AMOUNT - DECISION_SPLIT_AMOUNT_A);
    }

    function testSplitPositionB() public view {
        assertEq(conditionalMarketB.wrappedShort().balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(conditionalMarketB.wrappedLong().balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(userBalanceOutcomeB(), DECISION_SPLIT_AMOUNT - DECISION_SPLIT_AMOUNT_B);
    }

    function testSplitPositionC() public view {
        assertEq(conditionalMarketC.wrappedShort().balanceOf(USER), 0);
        assertEq(conditionalMarketC.wrappedLong().balanceOf(USER), 0);
        assertEq(userBalanceOutcomeC(), DECISION_SPLIT_AMOUNT);
    }

    function userBalanceOutcomeA() private view returns (uint256) {
        return conditionalTokens.balanceOf(
            USER,
            conditionalTokens.getPositionId(
                collateralToken,
                conditionalTokens.getCollectionId(
                    0, conditionalMarketA.parentConditionId(), 1 << conditionalMarketA.outcomeIndex()
                )
            )
        );
    }

    function userBalanceOutcomeB() private view returns (uint256) {
        return conditionalTokens.balanceOf(
            USER,
            conditionalTokens.getPositionId(
                collateralToken,
                conditionalTokens.getCollectionId(
                    0, conditionalMarketB.parentConditionId(), 1 << conditionalMarketB.outcomeIndex()
                )
            )
        );
    }

    function userBalanceOutcomeC() private view returns (uint256) {
        return conditionalTokens.balanceOf(
            USER,
            conditionalTokens.getPositionId(
                collateralToken,
                conditionalTokens.getCollectionId(
                    0, conditionalMarketC.parentConditionId(), 1 << conditionalMarketC.outcomeIndex()
                )
            )
        );
    }
}

contract TradeTestBase is SplitTestBase, ERC1155Holder {
    uint256 constant TRADE_AMOUNT = DECISION_SPLIT_AMOUNT / 4;
    uint256 constant CONTRACT_LIQUIDITY = INITIAL_SUPPLY / 100;
    SimpleAMM public ammA;
    SimpleAMM public ammB;
    SimpleAMM public ammC;
    uint256 constant DECISION_SPLIT_AMOUNT_C = DECISION_SPLIT_AMOUNT / 2;

    function setUp() public virtual override {
        super.setUp();

        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfm.conditionId(), decisionDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(CONTRACT_LIQUIDITY);
        conditionalMarketB.split(CONTRACT_LIQUIDITY);
        conditionalMarketC.split(CONTRACT_LIQUIDITY);

        ammA = new SimpleAMM(conditionalMarketA.wrappedShort(), conditionalMarketA.wrappedLong());
        vm.label(address(ammA), "amm A");
        ammB = new SimpleAMM(conditionalMarketB.wrappedShort(), conditionalMarketB.wrappedLong());
        vm.label(address(ammB), "amm B");
        ammC = new SimpleAMM(conditionalMarketC.wrappedShort(), conditionalMarketC.wrappedLong());
        vm.label(address(ammC), "amm C");

        conditionalMarketA.wrappedShort().approve(address(ammA), CONTRACT_LIQUIDITY);
        conditionalMarketA.wrappedLong().approve(address(ammA), CONTRACT_LIQUIDITY);
        ammA.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        conditionalMarketB.wrappedShort().approve(address(ammB), CONTRACT_LIQUIDITY);
        conditionalMarketB.wrappedLong().approve(address(ammB), CONTRACT_LIQUIDITY);
        ammB.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        conditionalMarketC.wrappedShort().approve(address(ammC), CONTRACT_LIQUIDITY);
        conditionalMarketC.wrappedLong().approve(address(ammC), CONTRACT_LIQUIDITY);
        ammC.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        vm.startPrank(USER);

        conditionalMarketA.wrappedShort().approve(address(ammA), TRADE_AMOUNT);
        ammA.swap(true, TRADE_AMOUNT);

        conditionalMarketB.wrappedShort().approve(address(ammB), TRADE_AMOUNT);
        ammB.swap(true, TRADE_AMOUNT);

        conditionalMarketC.split(DECISION_SPLIT_AMOUNT_C);
        conditionalMarketC.wrappedShort().approve(address(ammC), TRADE_AMOUNT * 2);
        ammC.swap(true, TRADE_AMOUNT * 2);

        vm.stopPrank();
    }

    function marketBalanceA(bool short) internal view returns (uint256) {
        return short
            ? conditionalMarketA.wrappedShort().balanceOf(address(ammA))
            : conditionalMarketA.wrappedLong().balanceOf(address(ammA));
    }

    function marketBalanceB(bool short) internal view returns (uint256) {
        return short
            ? conditionalMarketB.wrappedShort().balanceOf(address(ammB))
            : conditionalMarketB.wrappedLong().balanceOf(address(ammB));
    }

    function marketBalanceC(bool short) internal view returns (uint256) {
        return short
            ? conditionalMarketC.wrappedShort().balanceOf(address(ammC))
            : conditionalMarketC.wrappedLong().balanceOf(address(ammC));
    }
}

contract TradeTest is TradeTestBase {
    function testTradeOutcomeA() public view {
        assertTrue(conditionalMarketA.wrappedShort().balanceOf(USER) < DECISION_SPLIT_AMOUNT);
        assertTrue(conditionalMarketA.wrappedLong().balanceOf(USER) > DECISION_SPLIT_AMOUNT);
        assertTrue(marketBalanceA(true) > CONTRACT_LIQUIDITY);
        assertTrue(marketBalanceA(false) < CONTRACT_LIQUIDITY);
    }

    function testTradeOutcomeB() public view {
        assertEq(
            DECISION_SPLIT_AMOUNT / 2 - conditionalMarketB.wrappedShort().balanceOf(USER),
            DECISION_SPLIT_AMOUNT - conditionalMarketA.wrappedShort().balanceOf(USER)
        );
        assertEq(
            conditionalMarketB.wrappedLong().balanceOf(USER) - (DECISION_SPLIT_AMOUNT / 2),
            conditionalMarketA.wrappedLong().balanceOf(USER) - DECISION_SPLIT_AMOUNT
        );
        assertEq(marketBalanceA(true), marketBalanceB(true));
        assertEq(marketBalanceA(false), marketBalanceB(false));
    }

    function testTradeOutcomeC() public view {
        assertTrue(
            conditionalMarketC.wrappedShort().balanceOf(USER) < conditionalMarketB.wrappedShort().balanceOf(USER)
        );
        assertTrue(conditionalMarketC.wrappedLong().balanceOf(USER) > conditionalMarketB.wrappedLong().balanceOf(USER));
        assertTrue(marketBalanceC(true) > marketBalanceB(true));
        assertTrue(marketBalanceC(false) < marketBalanceB(false));
    }
}

contract MergeTestBase is TradeTestBase {
    uint256 constant MERGE_AMOUNT = DECISION_SPLIT_AMOUNT / 10;

    struct UserBalance {
        uint256 AShort;
        uint256 ALong;
        uint256 BShort;
        uint256 BLong;
        uint256 CShort;
        uint256 CLong;
    }

    UserBalance userBalanceBeforeMerge;

    function setUp() public virtual override {
        super.setUp();

        uint256 someTradeAmount = conditionalMarketC.wrappedLong().balanceOf(USER) / 4;

        vm.startPrank(USER);
        conditionalMarketC.wrappedLong().approve(address(ammC), someTradeAmount);
        ammC.swap(false, someTradeAmount);
        uint256 mergeMax = conditionalMarketC.wrappedShort().balanceOf(USER);

        userBalanceBeforeMerge = UserBalance({
            AShort: conditionalMarketA.wrappedShort().balanceOf(USER),
            ALong: conditionalMarketA.wrappedLong().balanceOf(USER),
            BShort: conditionalMarketB.wrappedShort().balanceOf(USER),
            BLong: conditionalMarketB.wrappedLong().balanceOf(USER),
            CShort: conditionalMarketC.wrappedShort().balanceOf(USER),
            CLong: conditionalMarketC.wrappedLong().balanceOf(USER)
        });

        conditionalMarketA.wrappedLong().approve(address(conditionalMarketA), MERGE_AMOUNT);
        conditionalMarketA.wrappedShort().approve(address(conditionalMarketA), MERGE_AMOUNT);
        conditionalMarketB.wrappedLong().approve(address(conditionalMarketB), MERGE_AMOUNT);
        conditionalMarketB.wrappedShort().approve(address(conditionalMarketB), MERGE_AMOUNT);
        conditionalMarketC.wrappedLong().approve(address(conditionalMarketC), mergeMax);
        conditionalMarketC.wrappedShort().approve(address(conditionalMarketC), mergeMax);

        conditionalMarketA.merge(MERGE_AMOUNT);
        conditionalMarketB.merge(MERGE_AMOUNT);
        conditionalMarketC.merge(mergeMax);

        vm.stopPrank();
    }
}

contract MergeTest is MergeTestBase {
    function testMergePositionsA() public view {
        assertEq(conditionalMarketA.wrappedShort().balanceOf(USER), userBalanceBeforeMerge.AShort - MERGE_AMOUNT);
        assertEq(conditionalMarketA.wrappedLong().balanceOf(USER), userBalanceBeforeMerge.ALong - MERGE_AMOUNT);
    }

    function testMergePositionsB() public view {
        assertEq(conditionalMarketB.wrappedShort().balanceOf(USER), userBalanceBeforeMerge.BShort - MERGE_AMOUNT);
        assertEq(conditionalMarketB.wrappedLong().balanceOf(USER), userBalanceBeforeMerge.BLong - MERGE_AMOUNT);
    }

    function testMergePositionsC() public view {
        // Merged all into collateral, so no wrapped short left.
        assertEq(conditionalMarketC.wrappedShort().balanceOf(USER), 0);
    }
}

//contract ResolveDecisionTest is MergeTest {}
//
//contract TradeAfterDecisionTest is ResolveDecisionTest {}
//
//contract ResolveConditionalsTest is TradeAfterDecisionTest {}
//
//contract RedeemTest is ResolveConditionalsTest {}
