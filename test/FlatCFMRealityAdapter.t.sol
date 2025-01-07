// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";
import "@realityeth/packages/contracts/development/contracts/IRealityETHCore.sol";

import "src/interfaces/IConditionalTokens.sol";
import "src/FlatCFMRealityAdapter.sol";
import {GenericScalarQuestionParams, ScalarParams} from "src/Types.sol";

import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyRealityETH} from "./dummy/RealityETH.sol";

contract Base is Test {
    FlatCFMRealityAdapter realityAdapter;
    DummyRealityETH reality;
    IConditionalTokens conditionalTokens;

    address arbitrator = address(0x123);
    uint256 decisionTemplateId = 1;
    uint256 metricTemplateId = 2;
    uint32 questionTimeout = 3600;
    uint256 minBond = 1 ether;

    function setUp() public virtual {
        reality = new DummyRealityETH();
        conditionalTokens = new DummyConditionalTokens();
        realityAdapter = new FlatCFMRealityAdapter(IRealityETH(address(reality)), arbitrator, questionTimeout, minBond);
    }
}

contract AskQuestionTest is Base {
    function testConstructor() public view {
        assertEq(address(realityAdapter.oracle()), address(reality));
        assertEq(realityAdapter.arbitrator(), arbitrator);
        assertEq(realityAdapter.questionTimeout(), questionTimeout);
        assertEq(realityAdapter.minBond(), minBond);
    }

    function testAskDecisionQuestion() public {
        FlatCFMQuestionParams memory flatCFMQuestionParams =
            FlatCFMQuestionParams({outcomeNames: new string[](2), openingTime: uint32(block.timestamp + 1000)});
        flatCFMQuestionParams.outcomeNames[0] = "Yes";
        flatCFMQuestionParams.outcomeNames[1] = "No";

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(DummyRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeDecisionQuestionId"))
        );
        bytes32 questionId = realityAdapter.askDecisionQuestion(decisionTemplateId, flatCFMQuestionParams);

        assertEq(questionId, bytes32("fakeDecisionQuestionId"));
    }

    function testAskMetricQuestion() public {
        GenericScalarQuestionParams memory params = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 10000000}),
            openingTime: uint32(block.timestamp + 1000)
        });

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(DummyRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeMetricQuestionId"))
        );
        bytes32 questionId = realityAdapter.askMetricQuestion(metricTemplateId, params, "Above $2000");
        assertEq(questionId, bytes32("fakeMetricQuestionId"));
    }

    function testEmptyOutcomeNames() public {
        FlatCFMQuestionParams memory params =
            FlatCFMQuestionParams({outcomeNames: new string[](0), openingTime: uint32(block.timestamp + 1000)});

        vm.expectRevert(); // Should revert with empty outcomes
        realityAdapter.askDecisionQuestion(decisionTemplateId, params);
    }
}

// From Reality //
// `resultForOnceSettled` reverts if TOO SOON.
// solhint-disable-next-line
// https://github.com/RealityETH/reality-eth-monorepo/blob/13f0556b72059e4a4d402fd75999d2ce320bd3c4/packages/contracts/tests/python/test.py#L2429
contract AnswerTest is Base {
    function testGetAnswer() public view {
        bytes32 questionId = bytes32("someQuestionId");
        bytes32 answer = realityAdapter.getAnswer(questionId);
        assertEq(answer, bytes32(0)); // Adjust expected value based on mock
    }

    function testGetAnswerRevertsIfNotSettled() public {
        bytes32 questionId = bytes32("someQuestionId");

        vm.mockCallRevert(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, questionId),
            "whatever"
        );

        vm.expectRevert();
        realityAdapter.getAnswer(questionId);
    }

    function testIsInvalid() public view {
        bytes32 invalidAnswer = bytes32(uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        assertTrue(realityAdapter.isInvalid(invalidAnswer));

        bytes32 validAnswer = bytes32(uint256(1));
        assertFalse(realityAdapter.isInvalid(validAnswer));
    }
}

contract ReportDecisionPayoutTest is Base {
    uint256 constant OUTCOME_COUNT = 50;
    bytes32 constant QUESTION_ID = bytes32("some question id");

    function testResolveGoodAnswerCallsReportPayouts() public {
        uint256[] memory plainAnswer = new uint256[](OUTCOME_COUNT);
        plainAnswer[0] = 1;
        plainAnswer[OUTCOME_COUNT - 1] = 1;
        bytes32 answer = _toBitArray(plainAnswer);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[0] = 1;
        expectedPayout[OUTCOME_COUNT - 1] = 1;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportDecisionPayouts(conditionalTokens, QUESTION_ID, OUTCOME_COUNT);
    }

    function testResolveWrongAnswerCallsReportPayoutsWithTruncatedContents() public {
        uint256[] memory plainAnswer = new uint256[](OUTCOME_COUNT + 2);
        plainAnswer[0] = 1;
        plainAnswer[OUTCOME_COUNT - 1] = 1;
        plainAnswer[OUTCOME_COUNT] = 1;
        bytes32 answer = _toBitArray(plainAnswer);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[0] = 1;
        expectedPayout[OUTCOME_COUNT - 1] = 1;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportDecisionPayouts(conditionalTokens, QUESTION_ID, OUTCOME_COUNT);
    }

    function testResolveEmptyAnswerReturnsLastPayout() public {
        uint256[] memory plainAnswer = new uint256[](OUTCOME_COUNT);
        bytes32 answer = _toBitArray(plainAnswer);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[OUTCOME_COUNT] = 1;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportDecisionPayouts(conditionalTokens, QUESTION_ID, OUTCOME_COUNT);
    }

    function testResolveInvalidReturnsLastPayout() public {
        bytes32 answer = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[OUTCOME_COUNT] = 1;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportDecisionPayouts(conditionalTokens, QUESTION_ID, OUTCOME_COUNT);
    }

    function testResolveRevertsWithRevertingResultForOnceSettled() public {
        vm.mockCallRevert(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            "whatever"
        );

        vm.expectRevert("whatever");
        realityAdapter.reportDecisionPayouts(conditionalTokens, QUESTION_ID, OUTCOME_COUNT);
    }

    // For example, [1,0,1] -> 0b101 represented by 0x05
    function _toBitArray(uint256[] memory plainAnswer) private pure returns (bytes32) {
        uint256 numericAnswer;
        for (uint256 i = 0; i < plainAnswer.length; i++) {
            numericAnswer |= (1 & plainAnswer[i]) << i;
        }
        return bytes32(numericAnswer);
    }
}

contract ReportMetricPayoutTest is Base {
    uint256 constant OUTCOME_COUNT = 50;
    bytes32 constant QUESTION_ID = bytes32("some question id");
    uint256 constant MIN_VALUE = 1000;
    uint256 constant MAX_VALUE = 11000;

    function testResolveGoodAnswerCallsReportPayouts() public {
        uint256 answer = 9000;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 2000;
        expectedPayout[1] = 8000;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportMetricPayouts(conditionalTokens, QUESTION_ID, MIN_VALUE, MAX_VALUE);
    }

    function testResolveAboveMaxAnswerReportsPayouts() public {
        uint256 answer = 1000000;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 0;
        expectedPayout[1] = 1;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportMetricPayouts(conditionalTokens, QUESTION_ID, MIN_VALUE, MAX_VALUE);
    }

    function testResolveBelowMinAnswerReportsPayouts() public {
        uint256 answer = 0;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 1;
        expectedPayout[1] = 0;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportMetricPayouts(conditionalTokens, QUESTION_ID, MIN_VALUE, MAX_VALUE);
    }

    function testResolveInvalidReturnsLastPayout() public {
        bytes32 answer = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[2] = 1;

        vm.mockCall(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        realityAdapter.reportMetricPayouts(conditionalTokens, QUESTION_ID, MIN_VALUE, MAX_VALUE);
    }

    function testResolveRevertsWithRevertingGetAnswer() public {
        vm.mockCallRevert(
            address(reality),
            abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, QUESTION_ID),
            "whatever"
        );

        vm.expectRevert("whatever");
        realityAdapter.reportMetricPayouts(conditionalTokens, QUESTION_ID, MIN_VALUE, MAX_VALUE);
    }
}
