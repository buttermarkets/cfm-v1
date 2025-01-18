// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./interfaces/IConditionalTokens.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

/// @title FlatCFMOracleAdapter
/// @notice Abstract adapter that defines how to ask decision and metric questions,
///         retrieve answers, and detect invalid outcomes.
abstract contract FlatCFMOracleAdapter {
    /// @notice Asks a "decision" (multi-outcome) question to the oracle.
    /// @param decisionTemplateId The template ID for the oracle's question format.
    /// @param flatCFMQuestionParams Includes outcome names and opening time.
    /// @return A unique questionId representing this question on the oracle.
    function askDecisionQuestion(uint256 decisionTemplateId, FlatCFMQuestionParams calldata flatCFMQuestionParams)
        external
        payable
        virtual
        returns (bytes32);

    /// @notice Asks a "metric" (scalar) question to the oracle.
    /// @param metricTemplateId The template ID for the oracle's scalar question format.
    /// @param genericScalarQuestionParams Struct containing scalar range data and opening time.
    /// @param outcomeName Descriptive name for this scalar outcome.
    /// @return A unique questionId representing this question on the oracle.
    function askMetricQuestion(
        uint256 metricTemplateId,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) external payable virtual returns (bytes32);

    /// @notice Gets the final answer for a previously asked question.
    /// @param questionId The question ID on the oracle.
    /// @return The raw answer as returned by the oracle.
    function getAnswer(bytes32 questionId) external view virtual returns (bytes32);

    /// @notice Checks if an answer indicates an invalid result.
    /// @param answer The oracle answer.
    /// @return True if the answer maps to an Invalid outcome, false otherwise.
    function isInvalid(bytes32 answer) external pure virtual returns (bool);
}
