// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol";
import {Arbitrator} from "@realityeth/packages/contracts/flat/Arbitrator-development.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";

import "./vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "./vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "./fake/SimpleAMM.sol";

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

    address USER = makeAddr("USER");

    uint256 public constant INITIAL_SUPPLY = 1000000 ether;
    uint256 public constant USER_SUPPLY = 5000 ether;
    uint256 public constant INITIAL_LIQUIDITY = 1000 ether;
    uint32 public constant QUESTION_TIMEOUT = 86400;
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
    FlatCFMFactory public factory;

    function setUp() public virtual override {
        super.setUp();
        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(arbitrator), QUESTION_TIMEOUT, MIN_BOND);
        factory = new FlatCFMFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );
    }
}

contract DeployCoreContractsTest is DeployCoreContractsBase {
    function testDecisionMarketFactoryDeployment() public view {
        assertTrue(address(factory) != address(0));
    }

    function testOracleAdapterDeployment() public view {
        assertTrue(address(oracleAdapter) != address(0));
    }
}

contract CreateDecisionMarketBase is DeployCoreContractsBase {
    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams genericScalarQuestionParams;
    CollateralToken public collateralToken;
    uint256 decisionTemplateId;
    uint256 metricTemplateId;
    FlatCFM cfm;
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;
    bytes32 cfmConditionId;

    function setUp() public virtual override {
        super.setUp();

        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");

        collateralToken.transfer(USER, USER_SUPPLY);

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Project A";
        outcomes[1] = "Project B";
        outcomes[2] = "Project C";

        decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomes, openingTime: uint32(block.timestamp + 2 days)});
        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 10000}),
            openingTime: uint32(block.timestamp + 90 days)
        });

        decisionTemplateId = reality.createTemplate(
            '{"title": "Which project will get funded?", "type": "uint", "category": "test", "lang": "en"}'
        );
        metricTemplateId = reality.createTemplate(
            // solhint-disable-next-line
            '{"title": "Between 2025-02-15 and 2025-06-15, what is the awesomeness in thousand USD, for %s on Coolchain?", "type": "uint", "category": "cfm-metric", "lang": "en"}'
        );

        vm.recordLogs();
        cfm = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }
        _recordConditionIdAndScalarMarkets();

        vm.label(address(cfm), "DecisionMarket");
        vm.label(address(conditionalMarketA), "ConditionalMarketA");
        vm.label(address(conditionalMarketB), "ConditionalMarketB");
        vm.label(address(conditionalMarketC), "ConditionalMarketC");
    }

    function _recordConditionIdAndScalarMarkets() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == keccak256("FlatCFMCreated(address,bytes32,address)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)
            ) {
                cfmConditionId = abi.decode(logs[i].data, (bytes32));
            }
            if (
                logs[i].topics[0] == keccak256("ConditionalScalarMarketCreated(address,address,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)
            ) {
                address csmAddr = address(uint160(uint256(logs[i].topics[2])));
                if (found == 0) {
                    conditionalMarketA = ConditionalScalarMarket(csmAddr);
                } else if (found == 1) {
                    conditionalMarketB = ConditionalScalarMarket(csmAddr);
                } else if (found == 2) {
                    conditionalMarketC = ConditionalScalarMarket(csmAddr);
                }
                found++;
            }
        }

        assertEq(found, 3, "wrong number of CSMs");
    }

    function _decisionDiscreetPartition() public view returns (uint256[] memory) {
        // +1 for Invalid
        uint256[] memory partition = new uint256[](cfm.outcomeCount() + 1);
        for (uint256 i = 0; i < cfm.outcomeCount() + 1; i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }
}

contract CreateDecisionMarketTest is CreateDecisionMarketBase {
    function testDecisionMarketCreated() public view {
        assertTrue(address(cfm) != address(0));
    }

    function testCfmConditionIdSet() public view {
        assertTrue(cfmConditionId != bytes32(0), "conditionId not found");
    }

    function testOutcomeCount() public view {
        assertEq(cfm.outcomeCount(), 3);
    }
}

contract CreateConditionalMarketsTest is CreateDecisionMarketBase {
    function testConditionalScalarMarketsCreated() public view {
        assertTrue(address(conditionalMarketA) != address(0), "Conditional market A not found");
        assertTrue(address(conditionalMarketB) != address(0), "Conditional market B not found");
        assertTrue(address(conditionalMarketC) != address(0), "Conditional market C not found");
    }

    function testParentCollectionIdA() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 0),
            "parent collection ID mismatch A"
        );
    }

    function testParentCollectionIdB() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 1),
            "parent collection ID mismatch B"
        );
    }

    function testParentCollectionIdC() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 2),
            "parent collection ID mismatch C"
        );
    }
}

contract SplitPositionTestBase is CreateDecisionMarketBase {
    uint256 constant DECISION_SPLIT_AMOUNT = USER_SUPPLY / 10;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);
        collateralToken.approve(address(conditionalTokens), DECISION_SPLIT_AMOUNT);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition(), DECISION_SPLIT_AMOUNT
        );
        vm.stopPrank();
    }
}

contract SplitPositionTest is SplitPositionTestBase {
    function testSplitPositionABalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 0),
            "parent collection ID mismatch A"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch"
        );
    }

    function testSplitPositionBBalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 1),
            "parent collection ID mismatch B"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch B"
        );
    }

    function testSplitPositionCBalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 2),
            "parent collection ID mismatch C"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch C"
        );
    }

    function testSplitPositionInvalidBalance() public view {
        assertEq(
            conditionalTokens.balanceOf(
                USER,
                conditionalTokens.getPositionId(
                    collateralToken, conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 3)
                )
            ),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch Invalid"
        );
    }
}

contract SplitTestBase is SplitPositionTestBase {
    uint256 constant METRIC_SPLIT_AMOUNT_A = DECISION_SPLIT_AMOUNT;
    uint256 constant METRIC_SPLIT_AMOUNT_B = DECISION_SPLIT_AMOUNT / 2;

    IERC20 wrappedShortA;
    IERC20 wrappedLongA;
    IERC20 wrappedInvalidA;
    IERC20 wrappedShortB;
    IERC20 wrappedLongB;
    IERC20 wrappedInvalidB;
    IERC20 wrappedShortC;
    IERC20 wrappedLongC;
    IERC20 wrappedInvalidC;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(METRIC_SPLIT_AMOUNT_A);
        conditionalMarketB.split(METRIC_SPLIT_AMOUNT_B);

        vm.stopPrank();

        (,,,,,, wrappedShortA, wrappedLongA, wrappedInvalidA) = conditionalMarketA.wrappedCTData();
        (,,,,,, wrappedShortB, wrappedLongB, wrappedInvalidB) = conditionalMarketB.wrappedCTData();
        (,,,,,, wrappedShortC, wrappedLongC, wrappedInvalidC) = conditionalMarketC.wrappedCTData();
    }

    function _userBalanceOutcomeA() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function _userBalanceOutcomeB() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function _userBalanceOutcomeC() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }
}

contract SplitTest is SplitTestBase {
    function testSplitPositionA() public view {
        assertEq(wrappedShortA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedInvalidA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(_userBalanceOutcomeA(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_A);
    }

    function testSplitPositionB() public view {
        assertEq(wrappedShortB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedLongB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedInvalidB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(_userBalanceOutcomeB(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_B);
    }

    function testSplitPositionC() public view {
        assertEq(wrappedShortC.balanceOf(USER), 0);
        assertEq(wrappedLongC.balanceOf(USER), 0);
        assertEq(wrappedInvalidC.balanceOf(USER), 0);
        assertEq(_userBalanceOutcomeC(), DECISION_SPLIT_AMOUNT);
    }
}

contract TradeTestBase is SplitTestBase, ERC1155Holder {
    uint256 constant TRADE_AMOUNT = USER_SUPPLY / 40;
    uint256 constant CONTRACT_LIQUIDITY = INITIAL_SUPPLY / 100;
    SimpleAMM public ammA;
    SimpleAMM public ammB;
    SimpleAMM public ammC;
    uint256 constant METRIC_SPLIT_AMOUNT_C = DECISION_SPLIT_AMOUNT / 2;

    function setUp() public virtual override {
        super.setUp();

        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(CONTRACT_LIQUIDITY);
        conditionalMarketB.split(CONTRACT_LIQUIDITY);
        conditionalMarketC.split(CONTRACT_LIQUIDITY);

        //(,,,,,, IERC20 shortA, IERC20 longA,) = conditionalMarketA.wrappedCTData();
        ammA = new SimpleAMM(wrappedShortA, wrappedLongA);
        vm.label(address(ammA), "amm A");
        //(,,,,,, IERC20 shortB, IERC20 longB,) = conditionalMarketB.wrappedCTData();
        ammB = new SimpleAMM(wrappedShortB, wrappedLongB);
        vm.label(address(ammB), "amm B");
        // (,,,,,, IERC20 shortC, IERC20 longC,) = conditionalMarketC.wrappedCTData();
        ammC = new SimpleAMM(wrappedShortC, wrappedLongC);
        vm.label(address(ammC), "amm C");

        wrappedShortA.approve(address(ammA), CONTRACT_LIQUIDITY);
        wrappedLongA.approve(address(ammA), CONTRACT_LIQUIDITY);
        ammA.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortB.approve(address(ammB), CONTRACT_LIQUIDITY);
        wrappedLongB.approve(address(ammB), CONTRACT_LIQUIDITY);
        ammB.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortC.approve(address(ammC), CONTRACT_LIQUIDITY);
        wrappedLongC.approve(address(ammC), CONTRACT_LIQUIDITY);
        ammC.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        vm.startPrank(USER);

        wrappedShortA.approve(address(ammA), TRADE_AMOUNT);
        ammA.swap(true, TRADE_AMOUNT);

        wrappedShortB.approve(address(ammB), TRADE_AMOUNT);
        ammB.swap(true, TRADE_AMOUNT);

        conditionalMarketC.split(METRIC_SPLIT_AMOUNT_C);
        wrappedShortC.approve(address(ammC), TRADE_AMOUNT * 2);
        ammC.swap(true, TRADE_AMOUNT * 2);

        vm.stopPrank();
    }

    function _marketBalanceA(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketA.wrappedCTData();
        return short ? wrappedShortA.balanceOf(address(ammA)) : wrappedLongA.balanceOf(address(ammA));
    }

    function _marketBalanceB(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketB.wrappedCTData();
        return short ? wrappedShortB.balanceOf(address(ammB)) : wrappedLongB.balanceOf(address(ammB));
    }

    function _marketBalanceC(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketC.wrappedCTData();
        return short ? wrappedShortC.balanceOf(address(ammC)) : wrappedLongC.balanceOf(address(ammC));
    }
}

contract TradeTest is TradeTestBase {
    function testTradeOutcomeA() public view {
        //(,,,,,, IERC20 sA, IERC20 lA,) = conditionalMarketA.wrappedCTData();
        assertTrue(wrappedShortA.balanceOf(USER) < DECISION_SPLIT_AMOUNT);
        assertTrue(wrappedLongA.balanceOf(USER) > DECISION_SPLIT_AMOUNT);
        assertTrue(_marketBalanceA(true) > CONTRACT_LIQUIDITY);
        assertTrue(_marketBalanceA(false) < CONTRACT_LIQUIDITY);
    }

    function testTradeOutcomeB() public view {
        //(,,,,,, IERC20 sA, IERC20 lA,) = conditionalMarketA.wrappedCTData();
        //(,,,,,, IERC20 sB, IERC20 lB,) = conditionalMarketB.wrappedCTData();
        assertEq(
            DECISION_SPLIT_AMOUNT / 2 - wrappedShortB.balanceOf(USER),
            DECISION_SPLIT_AMOUNT - wrappedShortA.balanceOf(USER)
        );
        assertEq(
            wrappedLongB.balanceOf(USER) - (DECISION_SPLIT_AMOUNT / 2),
            wrappedLongA.balanceOf(USER) - DECISION_SPLIT_AMOUNT
        );
        assertEq(_marketBalanceA(true), _marketBalanceB(true));
        assertEq(_marketBalanceA(false), _marketBalanceB(false));
    }

    function testTradeOutcomeC() public view {
        //(,,,,,, IERC20 sB, IERC20 lB,) = conditionalMarketB.wrappedCTData();
        //(,,,,,, IERC20 sC, IERC20 lC,) = conditionalMarketC.wrappedCTData();
        assertTrue(wrappedShortC.balanceOf(USER) < wrappedShortB.balanceOf(USER));
        assertTrue(wrappedLongC.balanceOf(USER) > wrappedLongB.balanceOf(USER));
        assertTrue(_marketBalanceC(true) > _marketBalanceB(true));
        assertTrue(_marketBalanceC(false) < _marketBalanceB(false));
    }
}

contract MergeTestBase is TradeTestBase {
    uint256 constant MERGE_AMOUNT = DECISION_SPLIT_AMOUNT / 10;

    struct UserBalance {
        uint256 AShort;
        uint256 ALong;
        uint256 AInvalid;
        uint256 BShort;
        uint256 BLong;
        uint256 BInvalid;
        uint256 CShort;
        uint256 CLong;
        uint256 CInvalid;
    }

    UserBalance userBalanceBeforeMerge;

    function setUp() public virtual override {
        super.setUp();

        uint256 someTradeAmount = wrappedLongC.balanceOf(USER) / 4;

        vm.startPrank(USER);
        wrappedLongC.approve(address(ammC), someTradeAmount);
        ammC.swap(false, someTradeAmount);
        uint256 mergeMax = wrappedShortC.balanceOf(USER);

        userBalanceBeforeMerge = UserBalance({
            AShort: wrappedShortA.balanceOf(USER),
            ALong: wrappedLongA.balanceOf(USER),
            AInvalid: wrappedInvalidA.balanceOf(USER),
            BShort: wrappedShortB.balanceOf(USER),
            BLong: wrappedLongB.balanceOf(USER),
            BInvalid: wrappedInvalidB.balanceOf(USER),
            CShort: wrappedShortC.balanceOf(USER),
            CLong: wrappedLongC.balanceOf(USER),
            CInvalid: wrappedInvalidC.balanceOf(USER)
        });

        wrappedLongA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedShortA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedInvalidA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedLongB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedShortB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedInvalidB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedLongC.approve(address(conditionalMarketC), mergeMax);
        wrappedShortC.approve(address(conditionalMarketC), mergeMax);
        wrappedInvalidC.approve(address(conditionalMarketC), mergeMax);

        conditionalMarketA.merge(MERGE_AMOUNT);
        conditionalMarketB.merge(MERGE_AMOUNT);
        conditionalMarketC.merge(mergeMax);

        vm.stopPrank();
    }
}

contract MergeTest is MergeTestBase {
    function testMergePositionsA() public view {
        assertEq(wrappedShortA.balanceOf(USER), userBalanceBeforeMerge.AShort - MERGE_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), userBalanceBeforeMerge.ALong - MERGE_AMOUNT);
    }

    function testMergePositionsB() public view {
        assertEq(wrappedShortB.balanceOf(USER), userBalanceBeforeMerge.BShort - MERGE_AMOUNT);
        assertEq(wrappedLongB.balanceOf(USER), userBalanceBeforeMerge.BLong - MERGE_AMOUNT);
    }

    function testMergePositionsC() public view {
        // Merged everything back into collateral
        assertEq(wrappedShortC.balanceOf(USER), 0);
    }
}

contract FormatAdapter is FlatCFMRealityAdapter {
    constructor() FlatCFMRealityAdapter(IRealityETH(address(0)), address(0), 0, 0) {}

    function formatDecisionQuestionParams(FlatCFMQuestionParams memory flatCFMQuestionParams)
        external
        pure
        returns (string memory)
    {
        return _formatDecisionQuestionParams(flatCFMQuestionParams);
    }

    function formatMetricQuestionParams(string memory outcomeName) external pure returns (string memory) {
        return _formatMetricQuestionParams(outcomeName);
    }
}

contract BadAnswerSubmitDecisionAnswerTest is MergeTestBase {
    address ANSWERER = makeAddr("answerer");

    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
    }

    function testCantResolveIfUnresolved() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question was settled too soon and has not been reopened");
        cfm.resolve();
    }

    function testCantResolveIfUnresolvedReopened() public {
        FormatAdapter formatAdapter = new FormatAdapter();

        vm.startPrank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(block.timestamp + QUESTION_TIMEOUT + 1);
        bytes32 newQuestionId = reality.reopenQuestion(
            decisionTemplateId,
            formatAdapter.formatDecisionQuestionParams(decisionQuestionParams),
            address(arbitrator),
            QUESTION_TIMEOUT,
            decisionQuestionParams.openingTime,
            0,
            MIN_BOND,
            cfm.questionId()
        );
        deal(ANSWERER, MIN_BOND);
        reality.submitAnswer{value: MIN_BOND}(
            newQuestionId, 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.stopPrank();

        vm.warp(block.timestamp + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question replacement was settled too soon and has not been reopened");
        cfm.resolve();
    }

    function testCanResolveIfInvalid() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0
        );

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 1);
    }

    function testCanResolveIfLargerValue() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(cfm.questionId(), bytes32(uint256(1 << cfm.outcomeCount() + 1)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 1);
    }
}

contract GoodAnswerSubmitDecisionAnswerTestBase is MergeTestBase {
    address ANSWERER = makeAddr("answerer");

    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(cfm.questionId(), /*0b101*/ bytes32(uint256(5)), 0);
    }
}

contract GoodAnswerSubmitDecisionAnswerTest is GoodAnswerSubmitDecisionAnswerTestBase {
    address CHALLENGER = makeAddr("challenger");

    function testCantResolveBeforeTimeout() public {
        vm.expectRevert("question must be finalized");
        cfm.resolve();
    }

    function testCantResolveAfterTimeoutIfChallenged() public {
        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND);

        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(cfm.questionId(), bytes32(uint256(1)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("question must be finalized");
        cfm.resolve();
    }

    function testCanResolveAfterChallengeTimeout() public {
        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND);
        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(cfm.questionId(), bytes32(uint256(3)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1 + QUESTION_TIMEOUT);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), (i == 0 || i == 1) ? 1 : 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 0);
    }
}

contract GoodAnswerCfmResolveTestBase is GoodAnswerSubmitDecisionAnswerTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();
    }
}

contract GoodAnswerCfmResolveTest is GoodAnswerCfmResolveTestBase {
    function testReportedPayouts() public view {
        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), (i == 0 || i == 2) ? 1 : 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 0);
    }
}

contract DecisionOutcomeRedeemTestBase is GoodAnswerCfmResolveTestBase {
    uint256 prevDeciRedeemBalanceA;
    uint256 prevDeciRedeemBalanceB;
    uint256 prevDeciRedeemBalanceC;
    uint256 prevDeciRedeemBalanceCollat;

    function setUp() public virtual override {
        super.setUp();

        prevDeciRedeemBalanceA = _userBalanceOutcomeA();
        prevDeciRedeemBalanceB = _userBalanceOutcomeB();
        prevDeciRedeemBalanceC = _userBalanceOutcomeC();
        prevDeciRedeemBalanceCollat = collateralToken.balanceOf(USER);

        vm.startPrank(USER);
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition());
        vm.stopPrank();
    }
}

contract DecisionOutcomeRedeemTest is DecisionOutcomeRedeemTestBase {
    function testRedeemUpdatesCollateralBalanceWithWinners() public view {
        uint256 expectedDeciRedeemCollatPayout = (prevDeciRedeemBalanceA + prevDeciRedeemBalanceC) / 2;
        assertEq(collateralToken.balanceOf(USER), prevDeciRedeemBalanceCollat + expectedDeciRedeemCollatPayout);
    }
}

contract BadAnswerSubmitMetricAsnwerTest is DecisionOutcomeRedeemTestBase {
    bytes32 csmAQuestionId;
    bytes32 csmAConditionId;

    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);

        (csmAQuestionId, csmAConditionId,,) = conditionalMarketA.ctParams();
    }

    function testCantResolveIfUnresolved() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question was settled too soon and has not been reopened");
        conditionalMarketA.resolve();
    }

    function testCanResolveIfInvalid() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 1);
    }

    function testCanResolveIfTooHigh() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, bytes32(uint256(genericScalarQuestionParams.scalarParams.maxValue + 1)), 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }

    function testCanResolveIfTooLow() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(csmAQuestionId, bytes32(uint256(0)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }
}

contract GoodAnswerSubmitMetricAnswerTestBase is DecisionOutcomeRedeemTestBase {
    bytes32 csmAQuestionId;
    bytes32 csmAConditionId;
    bytes32 csmAParentCollectionid;
    bytes32 csmBQuestionId;
    bytes32 csmBConditionId;
    bytes32 csmBParentCollectionid;
    bytes32 csmCQuestionId;
    bytes32 csmCConditionId;
    bytes32 csmCParentCollectionid;

    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND * 3);
        (csmAQuestionId, csmAConditionId, csmAParentCollectionid,) = conditionalMarketA.ctParams();
        (csmBQuestionId, csmBConditionId, csmBParentCollectionid,) = conditionalMarketB.ctParams();
        (csmCQuestionId, csmCConditionId, csmCParentCollectionid,) = conditionalMarketC.ctParams();
        vm.startPrank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(csmAQuestionId, bytes32(uint256(5000)), 0);
        reality.submitAnswer{value: MIN_BOND}(csmBQuestionId, bytes32(uint256(2500)), 0);
        reality.submitAnswer{value: MIN_BOND}(csmCQuestionId, bytes32(uint256(10000)), 0);
        vm.stopPrank();
    }
}

contract GoodAnswerSubmitMetricAnswerTest is GoodAnswerSubmitMetricAnswerTestBase {
    address CHALLENGER = makeAddr("challenger");

    function testCantResolveBeforeTimeout() public {
        vm.expectRevert("question must be finalized");
        conditionalMarketA.resolve();
    }

    function testCantResolveAfterTimeoutIfChallenged() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);

        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(csmAQuestionId, bytes32(uint256(1)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("question must be finalized");
        conditionalMarketA.resolve();
    }

    function testCanResolveAfterChallengeTimeout() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);
        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(csmAQuestionId, bytes32(uint256(0)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1 + QUESTION_TIMEOUT);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }
}

contract GoodAnswerCsmResolveTestBase is GoodAnswerSubmitMetricAnswerTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();
        conditionalMarketB.resolve();
        conditionalMarketC.resolve();
    }
}

contract GoodAnswerCsmResolveTest is GoodAnswerCsmResolveTestBase {
    function testReportedPayoutsA() public view {
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 5000);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 5000);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }

    function testReportedPayoutsB() public view {
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 0), 7500);
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 1), 2500);
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 2), 0);
    }

    function testReportedPayoutsC() public view {
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 1), 1);
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 2), 0);
    }
}

contract CsmRedeemTestBase is GoodAnswerCsmResolveTestBase {
    uint256 prevCondRedeemBalanceA;
    uint256 prevCondRedeemBalanceAShort;
    uint256 prevCondRedeemBalanceALong;
    uint256 prevCondRedeemBalanceAInvalid;
    uint256 prevCondRedeemBalanceB;
    uint256 prevCondRedeemBalanceBShort;
    uint256 prevCondRedeemBalanceBLong;
    uint256 prevCondRedeemBalanceBInvalid;
    uint256 prevCondRedeemBalanceC;
    uint256 prevCondRedeemBalanceCShort;
    uint256 prevCondRedeemBalanceCLong;
    uint256 prevCondRedeemBalanceCInvalid;

    function setUp() public virtual override {
        super.setUp();

        prevCondRedeemBalanceA = _userBalanceOutcomeA();
        prevCondRedeemBalanceAShort = wrappedShortA.balanceOf(USER);
        prevCondRedeemBalanceALong = wrappedLongA.balanceOf(USER);
        prevCondRedeemBalanceAInvalid = wrappedInvalidA.balanceOf(USER);
        prevCondRedeemBalanceB = _userBalanceOutcomeB();
        prevCondRedeemBalanceBShort = wrappedShortB.balanceOf(USER);
        prevCondRedeemBalanceBLong = wrappedLongB.balanceOf(USER);
        prevCondRedeemBalanceBInvalid = wrappedInvalidB.balanceOf(USER);
        prevCondRedeemBalanceC = _userBalanceOutcomeC();
        prevCondRedeemBalanceCShort = wrappedShortC.balanceOf(USER);
        prevCondRedeemBalanceCLong = wrappedLongC.balanceOf(USER);
        prevCondRedeemBalanceCInvalid = wrappedInvalidC.balanceOf(USER);

        vm.startPrank(USER);
        wrappedShortA.approve(address(conditionalMarketA), prevCondRedeemBalanceAShort);
        wrappedLongA.approve(address(conditionalMarketA), prevCondRedeemBalanceALong);
        wrappedInvalidA.approve(address(conditionalMarketA), prevCondRedeemBalanceAInvalid);
        wrappedShortB.approve(address(conditionalMarketB), prevCondRedeemBalanceBShort);
        wrappedLongB.approve(address(conditionalMarketB), prevCondRedeemBalanceBLong);
        wrappedInvalidB.approve(address(conditionalMarketB), prevCondRedeemBalanceBInvalid);
        wrappedShortC.approve(address(conditionalMarketC), prevCondRedeemBalanceCShort);
        wrappedLongC.approve(address(conditionalMarketC), prevCondRedeemBalanceCLong);
        wrappedInvalidC.approve(address(conditionalMarketC), prevCondRedeemBalanceCInvalid);
        conditionalMarketA.redeem(
            prevCondRedeemBalanceAShort, prevCondRedeemBalanceALong, prevCondRedeemBalanceAInvalid
        );
        conditionalMarketB.redeem(
            prevCondRedeemBalanceBShort, prevCondRedeemBalanceBLong, prevCondRedeemBalanceBInvalid
        );
        // Redeem half.
        conditionalMarketC.redeem(
            prevCondRedeemBalanceCShort / 2, prevCondRedeemBalanceCLong / 2, prevCondRedeemBalanceCInvalid / 2
        );
        vm.stopPrank();
    }
}

contract CsmRedeemTest is CsmRedeemTestBase {
    function testRedeemUpdatesOutcomeABalance() public view {
        assertEq(_userBalanceOutcomeA(), prevCondRedeemBalanceAShort / 2 + prevCondRedeemBalanceALong / 2);
    }

    function testRedeemUpdatesOutcomeBBalance() public view {
        assertEq(_userBalanceOutcomeB(), prevCondRedeemBalanceBShort * 3 / 4 + prevCondRedeemBalanceBLong / 4);
    }

    function testRedeemUpdatesOutcomeCBalance() public view {
        assertEq(_userBalanceOutcomeC(), prevCondRedeemBalanceCLong / 2);
        assertEq(wrappedLongC.balanceOf(USER), prevCondRedeemBalanceCLong / 2);
    }
}

contract RedeemBackToCollateralTest is CsmRedeemTestBase {
    uint256 prevFinalRedeemCollateralBalance;

    function setUp() public virtual override {
        super.setUp();

        prevFinalRedeemCollateralBalance = collateralToken.balanceOf(USER);

        vm.startPrank(USER);
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition());
        vm.stopPrank();
    }

    function testCollateral() public view {
        uint256 expectedPayout =
            (prevCondRedeemBalanceAShort / 2 + prevCondRedeemBalanceALong / 2) / 2 + prevCondRedeemBalanceCLong / 4;
        assertEq(collateralToken.balanceOf(USER), prevFinalRedeemCollateralBalance + expectedPayout);
    }
}
