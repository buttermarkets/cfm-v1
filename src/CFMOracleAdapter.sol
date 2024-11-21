// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {CFMDecisionQuestionParams, CFMConditionalQuestionParams} from "./QuestionTypes.sol";

abstract contract CFMOracleAdapter {
    function askDecisionQuestion(CFMDecisionQuestionParams calldata decisionQuestionParams)
        external
        virtual
        returns (bytes32);

    function askMetricQuestion(
        CFMConditionalQuestionParams calldata conditionalQuestionParams,
        string memory outcomeName
    ) external virtual returns (bytes32);

    function getAnswer(bytes32 questionID) external view virtual returns (bytes32);

    function isInvalid(bytes32 answer) external pure virtual returns (bool);
}
