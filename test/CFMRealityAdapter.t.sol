// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";

import "src/FlatCFMRealityAdapter.sol";
import {GenericScalarQuestionParams, ScalarParams} from "src/Types.sol";
import "src/vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import {FakeRealityETH} from "./FakeRealityETH.sol";

contract CFMRealityAdapterWithMockTest is Test {
    FlatCFMRealityAdapter realityAdapter;
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
        realityAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(fakeRealityEth)), arbitrator, questionTimeout, minBond);
    }

    function testConstructor() public view {
        assertEq(address(realityAdapter.oracle()), address(fakeRealityEth));
        assertEq(realityAdapter.arbitrator(), arbitrator);
        assertEq(realityAdapter.questionTimeout(), questionTimeout);
        assertEq(realityAdapter.minBond(), minBond);
    }

    function testAskDecisionQuestion() public {
        FlatCFMQuestionParams memory flatCFMQuestionParams = FlatCFMQuestionParams({
            roundName: "Round 1",
            outcomeNames: new string[](2),
            openingTime: uint32(block.timestamp + 1000)
        });
        flatCFMQuestionParams.outcomeNames[0] = "Yes";
        flatCFMQuestionParams.outcomeNames[1] = "No";

        vm.mockCall(
            address(fakeRealityEth),
            abi.encodeWithSelector(FakeRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeDecisionQuestionId"))
        );
        bytes32 questionId = realityAdapter.askDecisionQuestion(decisionTemplateId, flatCFMQuestionParams);

        // TODO: add integrated test.
        assertEq(questionId, bytes32("fakeDecisionQuestionId"));
    }

    function testAskMetricQuestion() public {
        GenericScalarQuestionParams memory params = GenericScalarQuestionParams({
            metricName: "ETH price",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: 0, maxValue: 10000000}),
            openingTime: uint32(block.timestamp + 1000)
        });

        vm.mockCall(
            address(fakeRealityEth),
            abi.encodeWithSelector(FakeRealityETH.askQuestionWithMinBond.selector),
            abi.encode(bytes32("fakeMetricQuestionId"))
        );
        bytes32 questionId = realityAdapter.askMetricQuestion(metricTemplateId, params, "Above $2000");
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
        FlatCFMQuestionParams memory params = FlatCFMQuestionParams({
            roundName: "Round 1",
            outcomeNames: new string[](0),
            openingTime: uint32(block.timestamp + 1000)
        });

        vm.expectRevert(); // Should revert with empty outcomes
        realityAdapter.askDecisionQuestion(decisionTemplateId, params);
    }
}
