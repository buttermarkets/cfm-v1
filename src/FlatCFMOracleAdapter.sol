// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

abstract contract FlatCFMOracleAdapter {
    function askDecisionQuestion(FlatCFMQuestionParams calldata flatCFMQuestionParams)
        external
        virtual
        returns (bytes32);

    function askMetricQuestion(
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) external virtual returns (bytes32);

    function getAnswer(bytes32 questionID) external view virtual returns (bytes32);

    function isInvalid(bytes32 answer) external pure virtual returns (bool);
}
