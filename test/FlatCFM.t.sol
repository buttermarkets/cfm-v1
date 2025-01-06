// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";

import "src/FlatCFM.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyFlatCFMOracleAdapter} from "./dummy/FlatCFMOracleAdapter.sol";

contract BaseTest is Test {
    FlatCFMOracleAdapter oracleAdapter;
    IConditionalTokens conditionalTokens;

    FlatCFM cfm;

    uint256 constant OUTCOME_COUNT = 50;
    bytes32 constant QUESTION_ID = bytes32("some question id");
    bytes32 constant CONDITION_ID = bytes32("some condition id");

    function setUp() public virtual {
        oracleAdapter = new DummyFlatCFMOracleAdapter();
        conditionalTokens = new DummyConditionalTokens();

        cfm = new FlatCFM(oracleAdapter, conditionalTokens, OUTCOME_COUNT, QUESTION_ID, CONDITION_ID);
    }
}

contract TestResolve is BaseTest {
    function testResolveGoodAnswerCallsReportPayouts() public {
        uint256[] memory plainAnswer = new uint256[](OUTCOME_COUNT);
        plainAnswer[0] = 1;
        plainAnswer[OUTCOME_COUNT - 1] = 1;
        bytes32 answer = _toBitArray(plainAnswer);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[0] = 1;
        expectedPayout[OUTCOME_COUNT - 1] = 1;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        cfm.resolve();
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
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        cfm.resolve();
    }

    function testResolveEmptyAnswerReturnsLastPayout() public {
        uint256[] memory plainAnswer = new uint256[](OUTCOME_COUNT);
        bytes32 answer = _toBitArray(plainAnswer);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[OUTCOME_COUNT] = 1;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(false)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        cfm.resolve();
    }

    function testResolveInvalidReturnsLastPayout() public {
        bytes32 answer = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        uint256[] memory expectedPayout = new uint256[](OUTCOME_COUNT + 1);
        expectedPayout[OUTCOME_COUNT] = 1;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector, answer),
            abi.encode(true)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        cfm.resolve();
    }

    function testResolveRevertsWithRevertingGetAnswer() public {
        vm.mockCallRevert(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            "whatever"
        );

        vm.expectRevert("whatever");
        cfm.resolve();
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
