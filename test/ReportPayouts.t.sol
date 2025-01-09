// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";

import "src/FlatCFMRealityAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import {CreateMarketTest} from "./FlatCFMFactory.t.sol";

contract FlatCFMReportPayoutsCoherenceTest is CreateMarketTest {
    address coherentAddress;

    function setUp() public override {
        super.setUp();
        coherentAddress = address(oracleAdapter);
    }

    function testPrepareConditionCoherentWithReportPayouts() public {
        // Provoke call to `prepareCondition`.
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            ),
            abi.encode(DECISION_QID)
        );
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.prepareCondition.selector, coherentAddress, DECISION_QID, outcomeNames.length + 1
            )
        );
        FlatCFM cfm = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );

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
        assertEq(conditionalTokens._test_reportPayouts_caller(), coherentAddress);
    }

    function _toBitArray(uint256[] memory plainAnswer) private pure returns (bytes32) {
        uint256 numericAnswer;
        for (uint256 i = 0; i < plainAnswer.length; i++) {
            numericAnswer |= (1 & plainAnswer[i]) << i;
        }
        return bytes32(numericAnswer);
    }
}

contract ConditionalScalarMarketReportPayoutsCoherenceTest is CreateMarketTest {
    address coherentAddress;

    function setUp() public override {
        super.setUp();
        coherentAddress = address(oracleAdapter);
    }

    function testPrepareConditionCoherentWithReportPayouts() public {
        // Provoke call to `prepareCondition`.
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(CONDITIONAL_QID)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.prepareCondition.selector, address(oracleAdapter), CONDITIONAL_QID, 3
            )
        );
        vm.recordLogs();
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );

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
        assertEq(conditionalTokens._test_reportPayouts_caller(), coherentAddress);
    }

    function _toBitArray(uint256[] memory plainAnswer) private pure returns (bytes32) {
        uint256 numericAnswer;
        for (uint256 i = 0; i < plainAnswer.length; i++) {
            numericAnswer |= (1 & plainAnswer[i]) << i;
        }
        return bytes32(numericAnswer);
    }
}
