// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

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
    string metadataUri;

    function setUp() public virtual {
        oracleAdapter = new DummyFlatCFMOracleAdapter();
        conditionalTokens = new DummyConditionalTokens();
        metadataUri = "ipfs://whatever";

        cfm = new FlatCFM(oracleAdapter, conditionalTokens, OUTCOME_COUNT, QUESTION_ID, CONDITION_ID, metadataUri);
    }
}

contract TestResolve is BaseTest {
    function testResolveToAdapter() public {
        vm.expectCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                DummyFlatCFMOracleAdapter.reportDecisionPayouts.selector, conditionalTokens, QUESTION_ID, OUTCOME_COUNT
            )
        );
        cfm.resolve();
    }
}
