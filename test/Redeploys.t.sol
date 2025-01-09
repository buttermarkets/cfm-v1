// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

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
    bytes32 constant CONDITIONAL_QID_2 = bytes32("diff conditional question id");
    bytes32 constant CONDITIONAL_CID_2 = bytes32("diff conditional condition id");
    bytes32 constant COND1_PARENT_COLLEC_ID_2 = bytes32("diff cond 1 parent collection id");
    bytes32 constant SHORT_COLLEC_ID_2 = bytes32("different short collection id");
    uint256 constant SHORT_POSID_2 = uint256(bytes32("different short position id"));
    bytes32 constant LONG_COLLEC_ID_2 = bytes32("different long collection id");
    uint256 constant LONG_POSID_2 = uint256(bytes32("different long position id"));

    IERC20 collateralToken2;
    FlatCFMQuestionParams decisionQuestionParams2;
    GenericScalarQuestionParams conditionalQuestionParams2;

    function setUp() public override {
        super.setUp();

        collateralToken2 = collateralToken;

        outcomeNames2.push("Project A");
        outcomeNames2.push("Project B");

        decisionQuestionParams2 =
            FlatCFMQuestionParams({outcomeNames: outcomeNames2, openingTime: DECISION_OPENING_TIME_2});

        conditionalQuestionParams = GenericScalarQuestionParams({
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
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
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
        factory.create(
            DECISION_TEMPLATE_ID_2,
            METRIC_TEMPLATE_ID_2,
            decisionQuestionParams2,
            conditionalQuestionParams2,
            collateralToken2,
            METADATA_URI_2
        );
        assertNotEq(args, args2);
    }
}

// TODO add integrated test for the repeat case.
// TODO this should rather be split in an interface test between FlatCFMFactory
// and FlatCFMRealityAdapter then a unit test in FlatCFMRealityAdapter.
contract CreateSameMarketsTest is CreateMarketTestBase {
    string realityQuestion;
    bytes32 questionId;
    bytes args;

    function setUp() public override {
        super.setUp();

        realityQuestion = "\"Project A\",\"Project B\",\"Project C\",\"Project D\"";
        bytes32 content_hash = keccak256(abi.encodePacked(DECISION_TEMPLATE_ID, DECISION_OPENING_TIME, realityQuestion));
        questionId = keccak256(
            abi.encodePacked(
                content_hash,
                oracleAdapter.arbitrator(),
                QUESTION_TIMEOUT,
                MIN_BOND,
                address(reality),
                address(oracleAdapter),
                uint256(0)
            )
        );

        args = abi.encodeWithSelector(
            IRealityETHCore.askQuestionWithMinBond.selector,
            DECISION_TEMPLATE_ID,
            realityQuestion,
            oracleAdapter.arbitrator(),
            QUESTION_TIMEOUT,
            DECISION_OPENING_TIME,
            0,
            MIN_BOND
        );
    }

    function testOneCallToAskQuestionWithMinBond() public {
        // Expect askQuestionWithMinBond to be called only once.
        vm.expectCall(address(reality), args, 1);
        FlatCFM cfm1 = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        FlatCFM cfm2 = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        assertEq(cfm1.questionId(), cfm2.questionId());
    }

    function testOneCallToPrepareCondition() public {
        // Expect prepareCondition to be called once only.
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.prepareCondition.selector,
                address(oracleAdapter),
                questionId,
                outcomeNames.length + 1
            ),
            1
        );
        FlatCFM cfm1 = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        FlatCFM cfm2 = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        assertEq(cfm1.conditionId(), cfm2.conditionId());
    }
}

// TODO test create another Factory and adapter then create with same params still works: same question
// TODO test create another Factory and adapter then create with same params still works: different condition
// TODO test create another Factory and same adapter then create with same params still works: same condition
