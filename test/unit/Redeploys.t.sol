// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMRealityAdapter.sol";
import "src/FlatCFMOracleAdapter.sol";

import {DummyRealityETH} from "./dummy/RealityETH.sol";
import {CreateMarketTestBase} from "./FlatCFMFactory.t.sol";

// QuestionID depends on:
// - template id
// - opening_ts
// - question
// - arbitrator
// - timeout
// - min_bond
// - Reality contract address
// - msg.sender, so oracle adapter
// - nonce
// solhint-disable-next-line
// See https://github.com/RealityETH/reality-eth-monorepo/blob/13f0556b72059e4a4d402fd75999d2ce320bd3c4/packages/contracts/flat/RealityETH-3.0.sol#L324

contract CreateDifferentMarketsTest is CreateMarketTestBase {
    string[] outcomeNames2;
    uint256 constant DECISION_TEMPLATE_ID_2 = DECISION_TEMPLATE_ID;
    uint256 constant METRIC_TEMPLATE_ID_2 = METRIC_TEMPLATE_ID;
    uint32 constant DECISION_OPENING_TIME_2 = 1739577600; // 2025-02-15
    string constant ROUND_NAME_2 = "other round";
    string constant METRIC_NAME_2 = "metric";
    string constant START_DATE_2 = "2025-02-16";
    string constant END_DATE_2 = "2025-06-16";
    uint256 constant MIN_VALUE_2 = 111;
    uint256 constant MAX_VALUE_2 = 333;
    uint32 constant METRIC_OPENING_TIME_2 = METRIC_OPENING_TIME; // 2025-06-17
    string METADATA_URI_2 = "";

    bytes32 constant DECISION_QID_2 = bytes32("different decision question id");
    bytes32 constant DECISION_CID_2 = bytes32("different decision condition id");
    bytes32 constant METRIC_QID_2 = bytes32("diff conditional question id");
    bytes32 constant METRIC_CID_2 = bytes32("diff conditional condition id");
    bytes32 constant COND1_PARENT_COLLEC_ID_2 = bytes32("diff cond 1 parent collection id");
    bytes32 constant SHORT_COLLEC_ID_2 = bytes32("different short collection id");
    uint256 constant SHORT_POSID_2 = uint256(bytes32("different short position id"));
    bytes32 constant LONG_COLLEC_ID_2 = bytes32("different long collection id");
    uint256 constant LONG_POSID_2 = uint256(bytes32("different long position id"));

    IERC20 collateralToken2;
    FlatCFMQuestionParams decisionQuestionParams2;
    GenericScalarQuestionParams genericScalarQuestionParams2;

    function setUp() public override {
        super.setUp();

        collateralToken2 = collateralToken;

        outcomeNames2.push("Project A");
        outcomeNames2.push("Project B");

        decisionQuestionParams2 =
            FlatCFMQuestionParams({outcomeNames: outcomeNames2, openingTime: DECISION_OPENING_TIME_2});

        genericScalarQuestionParams2 = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE_2, maxValue: MAX_VALUE_2}),
            openingTime: METRIC_OPENING_TIME_2
        });
    }

    function testCallsPrepare() public {
        bytes memory args = abi.encodeWithSelector(
            IRealityETHCore.askQuestionWithMinBond.selector,
            DECISION_TEMPLATE_ID,
            "\"Project A\",\"Project B\",\"Project C\",\"Project D\"",
            oracleAdapter.arbitrator(),
            QUESTION_TIMEOUT,
            DECISION_OPENING_TIME,
            0,
            MIN_BOND
        );

        vm.expectCall(address(reality), args);

        FlatCFM cfm1 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm1);
        }

        bytes memory args2 = abi.encodeWithSelector(
            IRealityETHCore.askQuestionWithMinBond.selector,
            DECISION_TEMPLATE_ID_2,
            "\"Project A\",\"Project B\"",
            oracleAdapter.arbitrator(),
            QUESTION_TIMEOUT,
            DECISION_OPENING_TIME_2,
            0,
            MIN_BOND
        );

        vm.expectCall(address(reality), args2);

        FlatCFM cfm2 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID_2,
            METRIC_TEMPLATE_ID_2,
            decisionQuestionParams2,
            genericScalarQuestionParams2,
            collateralToken2,
            METADATA_URI_2
        );
        for (uint256 i = 0; i < decisionQuestionParams2.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm2);
        }

        assertNotEq(args, args2);
    }
}

// TODO add integrated test for the repeat case.
// TODO this should rather be split in an interface test between FlatCFMFactory
// and FlatCFMRealityAdapter then a unit test in FlatCFMRealityAdapter.
contract CreateSameMarketsTest is CreateMarketTestBase {
    string decisionRealityQuestion;

    function setUp() public override {
        super.setUp();

        decisionRealityQuestion = "\"Project A\",\"Project B\",\"Project C\",\"Project D\"";
    }

    function testOneCallToAskQuestionWithMinBondDecision() public {
        // Expect askQuestionWithMinBond to be called only once for the same decision question.
        vm.expectCall(
            address(reality),
            abi.encodeWithSelector(
                IRealityETHCore.askQuestionWithMinBond.selector,
                DECISION_TEMPLATE_ID,
                "\"Project A\",\"Project B\",\"Project C\",\"Project D\"",
                oracleAdapter.arbitrator(),
                QUESTION_TIMEOUT,
                DECISION_OPENING_TIME,
                0,
                MIN_BOND
            ),
            1
        );

        vm.recordLogs();

        // 1) Create first FlatCFM
        FlatCFM cfm1 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm1);
        }

        // 2) Create second FlatCFM with identical parameters
        FlatCFM cfm2 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm2);
        }

        // Same questionId expected for both, indicating only one underlying reality question
        assertEq(cfm1.questionId(), cfm2.questionId());
    }

    function testOneCallToAskQuestionWithMinBondScalar() public {
        // Expect askQuestionWithMinBond to be called only once per unique metric question.
        vm.expectCall(
            address(reality),
            abi.encodeWithSelector(
                IRealityETHCore.askQuestionWithMinBond.selector,
                METRIC_TEMPLATE_ID,
                "Project A",
                oracleAdapter.arbitrator(),
                QUESTION_TIMEOUT,
                METRIC_OPENING_TIME,
                0,
                MIN_BOND
            ),
            1
        );

        vm.recordLogs();

        // 1) Create first FlatCFM
        FlatCFM cfm1 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm1);
        }

        // Grab first child market
        ConditionalScalarMarket csm1 = _getFirstConditionalScalarMarket();

        // 2) Create second FlatCFM with identical parameters
        FlatCFM cfm2 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm2);
        }

        // Grab second child market
        ConditionalScalarMarket csm2 = _getFirstConditionalScalarMarket();

        // Both child markets share the same metric question
        (bytes32 qid1,,,) = csm1.ctParams();
        (bytes32 qid2,,,) = csm2.ctParams();
        assertEq(qid1, qid2);
    }

    function testDuplicateCallsToPrepareCondition() public {
        // We expect multiple calls to prepareCondition:
        // - 1 for each new FlatCFM's parent condition
        // - plus child conditions for each outcome in each deployment.
        // The old logic: "2 * 1 + 2 * #outcomes" might be approximate, depending on how many times we reuse conditions.
        uint64 count = 2 * 1 + 2 * uint64(decisionQuestionParams.outcomeNames.length);

        vm.expectCall(
            address(conditionalTokens), abi.encodeWithSelector(IConditionalTokens.prepareCondition.selector), count
        );

        vm.recordLogs();

        // 1) Create first FlatCFM + child markets
        FlatCFM cfm1 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm1);
        }
        ConditionalScalarMarket csm1 = _getFirstConditionalScalarMarket();

        // 2) Create second FlatCFM + child markets
        FlatCFM cfm2 = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm2);
        }
        ConditionalScalarMarket csm2 = _getFirstConditionalScalarMarket();

        // Both CFMs should share the same underlying questionId
        assertEq(cfm1.questionId(), cfm2.questionId());
        assertEq(cfm1.outcomeCount(), cfm2.outcomeCount());

        // Their child markets also share the same metric question
        (bytes32 qid1,,,) = csm1.ctParams();
        (bytes32 qid2,,,) = csm2.ctParams();
        assertEq(qid1, qid2);
    }
}

// TODO test create another Factory and adapter then create with same params still works: same question
// TODO test create another Factory and adapter then create with same params still works: different condition
// TODO test create another Factory and same adapter then create with same params still works: same condition
