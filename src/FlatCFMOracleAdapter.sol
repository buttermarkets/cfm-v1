// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {FlatCFMQuestionParams, ScalarQuestionParams} from "./QuestionTypes.sol";

abstract contract FlatCFMOracleAdapter {
    function askDecisionQuestion(FlatCFMQuestionParams calldata decisionQuestionParams)
        external
        virtual
        returns (bytes32);

    function askMetricQuestion(ScalarQuestionParams calldata conditionalQuestionParams, string memory outcomeName)
        external
        virtual
        returns (bytes32);

    function getAnswer(bytes32 questionID) external view virtual returns (bytes32);

    function isInvalid(bytes32 answer) external pure virtual returns (bool);
}
