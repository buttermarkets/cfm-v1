// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CFMDecisionQuestionParams, CFMConditionalQuestionParams} from "./QuestionTypes.sol";

interface ICFMOracleAdapter {
    function askDecisionQuestion(CFMDecisionQuestionParams calldata decisionQuestionParams)
        external
        returns (bytes32);

    function askMetricQuestion(
        CFMConditionalQuestionParams calldata conditionalQuestionParams,
        string memory outcomeName
    ) external returns (bytes32);

    function getAnswer(bytes32 questionID) external view returns (bytes32);

    function isInvalid(bytes32 answer) external pure returns (bool);
}
