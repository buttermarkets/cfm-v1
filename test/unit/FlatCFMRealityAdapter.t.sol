// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

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
            abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector),
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
            abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector),
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

contract ValueCheckingReality {
    function askQuestionWithMinBond(uint256, string memory, address, uint32, uint32, uint256, uint256)
        external
        payable
        virtual
        returns (bytes32)
    {
        require(msg.value >= 1 ether, "ETH provided must cover question fee");
        return keccak256("dummy");
    }
}

// These tests mock the `askQuestionWithMinBond` to revert as if the
// arbitration fee is non-null.
// solhint-disable-next-line
// See https://github.com/RealityETH/reality-eth-monorepo/blob/13f0556b72059e4a4d402fd75999d2ce320bd3c4/packages/contracts/flat/RealityETH-3.0.sol#L352
contract AskDecisionQuestionPaymentTest is Base {
    FlatCFMQuestionParams flatCFMQuestionParams;

    function setUp() public override {
        super.setUp();

        flatCFMQuestionParams =
            FlatCFMQuestionParams({outcomeNames: new string[](3), openingTime: uint32(block.timestamp + 1000)});
        flatCFMQuestionParams.outcomeNames[0] = "A";
        flatCFMQuestionParams.outcomeNames[1] = "B";
        flatCFMQuestionParams.outcomeNames[2] = "C";
    }

    function testAskDecisionQuestionForwardsPayment(uint256 sendValue) public {
        vm.assume(sendValue >= 1 ether);
        deal(address(this), sendValue);

        vm.expectCall(
            address(reality), sendValue, abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector)
        );
        realityAdapter.askDecisionQuestion{value: sendValue}(decisionTemplateId, flatCFMQuestionParams);
    }

    function testAskDecisionQuestionWithoutEnoughPaymentReverts(uint256 sendValue) public {
        sendValue = bound(sendValue, 0, 1 ether);
        vm.assume(sendValue < 1 ether);
        deal(address(this), sendValue);

        ValueCheckingReality valueCheckingRealityModel = new ValueCheckingReality();
        vm.mockFunction(
            address(reality),
            address(valueCheckingRealityModel),
            abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector)
        );

        vm.expectRevert("ETH provided must cover question fee");
        realityAdapter.askDecisionQuestion{value: sendValue}(decisionTemplateId, flatCFMQuestionParams);
    }
}

contract AskMetricQuestionPaymentTest is Base {
    GenericScalarQuestionParams genericScalarQuestionParams;

    function setUp() public override {
        super.setUp();

        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 10000000}),
            openingTime: uint32(block.timestamp + 1000)
        });
    }

    function testAskMetricQuestionForwardsPayment(uint256 sendValue) public {
        vm.assume(sendValue >= 1 ether);
        deal(address(this), sendValue);

        vm.expectCall(
            address(reality), sendValue, abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector)
        );
        realityAdapter.askMetricQuestion{value: sendValue}(metricTemplateId, genericScalarQuestionParams, "A");
    }

    function testAskMetricQuestionWithoutEnoughPaymentReverts(uint256 sendValue) public {
        sendValue = bound(sendValue, 0, 1 ether);
        vm.assume(sendValue < 1 ether);
        deal(address(this), sendValue);

        ValueCheckingReality valueCheckingRealityModel = new ValueCheckingReality();
        vm.mockFunction(
            address(reality),
            address(valueCheckingRealityModel),
            abi.encodeWithSelector(IRealityETHCore.askQuestionWithMinBond.selector)
        );

        vm.expectRevert("ETH provided must cover question fee");
        realityAdapter.askMetricQuestion{value: sendValue}(metricTemplateId, genericScalarQuestionParams, "A");
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

contract GetAnswerTest is Base {
    function testGetAnswerToReality(bytes32 questionId) public {
        vm.expectCall(
            address(reality), abi.encodeWithSelector(IRealityETHCore.resultForOnceSettled.selector, questionId)
        );
        realityAdapter.getAnswer(questionId);
    }
}
