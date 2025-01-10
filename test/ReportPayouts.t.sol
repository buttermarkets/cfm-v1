// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";

import "src/FlatCFMRealityAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import {CreateMarketTestBase} from "./FlatCFMFactory.t.sol";

contract FlatCFMReportPayoutsCoherenceTest is CreateMarketTestBase {
    function testPrepareConditionCoherentWithReportPayouts() public {
        // Provoke call to `prepareCondition`.
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            ),
            abi.encode(DECISION_QID)
        );
        vm.recordLogs();
        FlatCFM cfm = factory.create(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        address firstOracle = conditionalTokens._test_prepareCondition_oracle(DECISION_QID);

        // Provoke call to `reportPayout`.
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
        outcomeNames.pop();
        outcomeNames.pop();
        outcomeNames.pop();

        decisionQuestionParams = FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: DECISION_OPENING_TIME});

        conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: METRIC_OPENING_TIME
        });
    }

    function testPrepareConditionCoherentWithReportPayouts() public {
        // Provoke call to `prepareCondition`.
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(CONDITIONAL_QID)
        );

        vm.recordLogs();
        factory.create(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
        address firstOracle = conditionalTokens._test_prepareCondition_oracle(CONDITIONAL_QID);

        // Provoke call to `reportPayout`.
        uint256 answer = MAX_VALUE;
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, CONDITIONAL_QID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );
        ConditionalScalarMarket csm1 = _getFirstConditionalScalarMarket();
        csm1.resolve();
        address secondOracle = conditionalTokens._test_reportPayouts_caller(CONDITIONAL_QID);

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
