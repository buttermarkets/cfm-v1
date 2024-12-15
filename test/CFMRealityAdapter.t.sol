// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";

import "../src/butter-v1/CFMRealityAdapter.sol";
import "../src/ConditionalTokens.sol";
import {FakeRealityETH} from "./FakeRealityETH.sol";

contract CFMRealityAdapterWithMockTest is Test {
    CFMRealityAdapter realityAdapter;
    FakeRealityETH fakeRealityEth;
    ConditionalTokens conditionalTokens;

    address arbitrator = address(0x123);
    uint256 decisionTemplateId = 1;
    uint256 metricTemplateId = 2;
    uint32 questionTimeout = 3600;
    uint256 minBond = 1 ether;

    function setUp() public {
        fakeRealityEth = new FakeRealityETH();
        conditionalTokens = new ConditionalTokens();
        realityAdapter = new CFMRealityAdapter(
            IRealityETH(address(fakeRealityEth)),
            arbitrator,
            decisionTemplateId,
            metricTemplateId,
            questionTimeout,
            minBond
        );
    }

    function testConstructor() public view {
        assertEq(address(realityAdapter.oracle()), address(fakeRealityEth));
        assertEq(realityAdapter.arbitrator(), arbitrator);
        assertEq(realityAdapter.decisionTemplateId(), decisionTemplateId);
        assertEq(realityAdapter.metricTemplateId(), metricTemplateId);
        assertEq(realityAdapter.questionTimeout(), questionTimeout);
        assertEq(realityAdapter.minBond(), minBond);
    }

    function testAskDecisionQuestion() public {
        CFMDecisionQuestionParams memory decisionQuestionParams = CFMDecisionQuestionParams({
            roundName: "Round 1",
            outcomeNames: new string[](2),
            openingTime: uint32(block.timestamp + 1000)
        });
        decisionQuestionParams.outcomeNames[0] = "Yes";
        decisionQuestionParams.outcomeNames[1] = "No";

        vm.mockCall(
            address(fakeRealityEth),
            abi.encodeWithSelector(FakeRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeDecisionQuestionId"))
        );
        bytes32 questionId = realityAdapter.askDecisionQuestion(decisionQuestionParams);

        // TODO: add integrated test.
        assertEq(questionId, bytes32("fakeDecisionQuestionId"));
    }

    function testAskMetricQuestion() public {
        CFMConditionalQuestionParams memory params = CFMConditionalQuestionParams({
            metricName: "ETH price",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            minValue: 0,
            maxValue: 10000000,
            openingTime: uint32(block.timestamp + 1000)
        });

        vm.mockCall(
            address(fakeRealityEth),
            abi.encodeWithSelector(FakeRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeMetricQuestionId"))
        );
        bytes32 questionId = realityAdapter.askMetricQuestion(params, "Above $2000");
        assertEq(questionId, bytes32("fakeMetricQuestionId"));
    }

    function testGetAnswer() public view {
        bytes32 questionId = bytes32("someQuestionId");
        bytes32 answer = realityAdapter.getAnswer(questionId);
        assertEq(answer, bytes32(0)); // Adjust expected value based on mock
    }

    function testIsInvalid() public view {
        bytes32 invalidAnswer = bytes32(uint256(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff));
        assertTrue(realityAdapter.isInvalid(invalidAnswer));

        bytes32 validAnswer = bytes32(uint256(1));
        assertFalse(realityAdapter.isInvalid(validAnswer));
    }

    function testEmptyOutcomeNames() public {
        CFMDecisionQuestionParams memory params = CFMDecisionQuestionParams({
            roundName: "Round 1",
            outcomeNames: new string[](0),
            openingTime: uint32(block.timestamp + 1000)
        });

        vm.expectRevert(); // Should revert with empty outcomes
        realityAdapter.askDecisionQuestion(params);
    }
}
