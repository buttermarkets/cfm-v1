// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/src/Test.sol";

import "../src/butter-v1/CFMRealityAdapter.sol";
import "../src/ConditionalTokens.sol";
import {MockRealityETH} from "./MockRealityETH.sol";

contract CFMRealityAdapterTest is Test {
    CFMRealityAdapter realityAdapter;
    MockRealityETH mockRealitio;
    ConditionalTokens conditionalTokens;

    address arbitrator = address(0x123);
    uint256 decisionTemplateId = 1;
    uint256 metricTemplateId = 2;
    uint32 questionTimeout = 3600;
    uint256 minBond = 1 ether;

    function setUp() public {
        mockRealitio = new MockRealityETH();
        conditionalTokens = new ConditionalTokens();
        realityAdapter = new CFMRealityAdapter(
            IRealityETH(address(mockRealitio)),
            arbitrator,
            decisionTemplateId,
            metricTemplateId,
            questionTimeout,
            minBond
        );
    }

    function testConstructor() public view {
        assertEq(address(realityAdapter.oracle()), address(mockRealitio));
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

        bytes32 questionId = realityAdapter.askDecisionQuestion(decisionQuestionParams);
        //bytes32 expectedId = keccak256(
        //    abi.encodePacked(
        //        decisionTemplateId,
        //        decisionQuestionParams.openingTime,
        //        string(abi.encodePacked("Round 1", "\u241f", "\"Yes\",\"No\""))
        //    )
        //);

        assertEq(questionId, bytes32("minbondreturn"));
    }

    // Additional tests can be added here
}
