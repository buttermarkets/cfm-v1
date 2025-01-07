// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import "./interfaces/IConditionalTokens.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

abstract contract FlatCFMOracleAdapter {
    function askDecisionQuestion(uint256 decisionTemplateId, FlatCFMQuestionParams calldata flatCFMQuestionParams)
        external
        virtual
        returns (bytes32);

    function askMetricQuestion(
        uint256 metricTemplateId,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) external virtual returns (bytes32);

    function reportDecisionPayouts(IConditionalTokens conditionalTokens, bytes32 questionId, uint256 outcomeCount)
        external
        virtual;
    function reportMetricPayouts(
        IConditionalTokens conditionalTokens,
        bytes32 questionId,
        uint256 minValue,
        uint256 maxValue
    ) external virtual;

    function getAnswer(bytes32 questionId) external view virtual returns (bytes32);

    function isInvalid(bytes32 answer) external pure virtual returns (bool);
}
