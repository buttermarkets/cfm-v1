// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";

import "src/FlatCFMRealityAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import {CreateMarketTestBase} from "./FlatCFMFactory.t.sol";

contract FlatCFMReportPayoutsCoherenceTest is CreateMarketTestBase {
    function testPrepareConditionCoherentWithReportPayouts() public {
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            ),
            abi.encode(DECISION_QID)
        );

        vm.recordLogs();

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        address firstOracle = conditionalTokens._test_prepareCondition_oracle(DECISION_QID);

        uint256[] memory plainAnswer = new uint256[](outcomeNames.length);
        plainAnswer[0] = 1;
        bytes32 answer = _toBitArray(plainAnswer);

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, DECISION_QID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );

        cfm.resolve();
        address secondOracle = conditionalTokens._test_reportPayouts_caller(DECISION_QID);

        assertEq(firstOracle, secondOracle);
    }

    function _toBitArray(uint256[] memory plainAnswer) private pure returns (bytes32) {
        uint256 numericAnswer;
        for (uint256 i = 0; i < plainAnswer.length; i++) {
            numericAnswer |= (1 & plainAnswer[i]) << i;
        }
        return bytes32(numericAnswer);
    }
}

contract ConditionalScalarMarketReportPayoutsCoherenceTest is CreateMarketTestBase {
    function setUp() public virtual override {
        super.setUp();
        // Keep only 1 outcome in outcomeNames (popped 3 from the default 4).
        outcomeNames.pop();
        outcomeNames.pop();
        outcomeNames.pop();

        decisionQuestionParams = FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: DECISION_OPENING_TIME});

        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: METRIC_OPENING_TIME
        });
    }

    function testPrepareConditionCoherentWithReportPayouts() public {
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(METRIC_QID)
        );

        vm.recordLogs();

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        address firstOracle = conditionalTokens._test_prepareCondition_oracle(METRIC_QID);

        uint256 answer = MAX_VALUE;
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, METRIC_QID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );

        ConditionalScalarMarket csm1 = _getFirstConditionalScalarMarket();
        csm1.resolve();

        address secondOracle = conditionalTokens._test_reportPayouts_caller(METRIC_QID);
        assertEq(firstOracle, secondOracle);
    }

    function _toBitArray(uint256[] memory plainAnswer) private pure returns (bytes32) {
        uint256 numericAnswer;
        for (uint256 i = 0; i < plainAnswer.length; i++) {
            numericAnswer |= (1 & plainAnswer[i]) << i;
        }
        return bytes32(numericAnswer);
    }
}
