// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";
import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

/// @title FlatCFMRealityAdapter
/// @notice Adapter that connects a flat CFM (decision market) interface to the Reality.eth oracle.
contract FlatCFMRealityAdapter is FlatCFMOracleAdapter {
    /// @notice Reference to the RealityETH oracle contract.
    IRealityETH public immutable oracle;

    /// @notice The arbitrator address used by RealityETH for dispute resolution.
    address public immutable arbitrator;

    /// @notice The time (in seconds) that a question must be finalized before the answer is locked.
    uint32 public immutable questionTimeout;

    /// @notice The minimum bond required to ask a question on RealityETH.
    uint256 public immutable minBond;

    /// @notice Thrown if the question is stuck or otherwise unresolvable.
    error QuestionStuck(address questionId);

    /// @param _oracle The RealityETH oracle contract.
    /// @param _arbitrator The arbitrator address used for disputes.
    /// @param _questionTimeout Timeout in seconds for finalizing a question.
    /// @param _minBond Minimum bond required by RealityETH for asking a question.
    constructor(IRealityETH _oracle, address _arbitrator, uint32 _questionTimeout, uint256 _minBond) {
        oracle = _oracle;
        arbitrator = _arbitrator;
        questionTimeout = _questionTimeout;
        minBond = _minBond;
    }

    /// @notice Asks a multi-outcome (decision) question on RealityETH.
    /// @param decisionTemplateId Template ID for the question.
    /// @param flatCFMQuestionParams Struct with outcome names and the opening time.
    /// @return The RealityETH question ID.
    function askDecisionQuestion(uint256 decisionTemplateId, FlatCFMQuestionParams calldata flatCFMQuestionParams)
        public
        payable
        override
        returns (bytes32)
    {
        string memory formattedDecisionQuestionParams = _formatDecisionQuestionParams(flatCFMQuestionParams);
        return _askQuestion(decisionTemplateId, formattedDecisionQuestionParams, flatCFMQuestionParams.openingTime);
    }

    /// @notice Asks a scalar (metric) question on RealityETH.
    /// @param metricTemplateId Template ID for the metric (scalar) question.
    /// @param genericScalarQuestionParams Contains the scalar range and opening time.
    /// @param outcomeName Human-readable name for this metric.
    /// @return The RealityETH question ID.
    function askMetricQuestion(
        uint256 metricTemplateId,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) public payable override returns (bytes32) {
        string memory formattedMetricQuestionParams = _formatMetricQuestionParams(outcomeName);
        return _askQuestion(metricTemplateId, formattedMetricQuestionParams, genericScalarQuestionParams.openingTime);
    }

    /// @notice Gets the final answer for a question from RealityETH.
    /// @dev Reverts if the question is not finalized.
    /// @param questionId The RealityETH question ID.
    /// @return The raw, finalized answer.
    function getAnswer(bytes32 questionId) public view override returns (bytes32) {
        return oracle.resultForOnceSettled(questionId);
    }

    /// @notice Checks if an answer is RealityETH's 'Invalid' (all bits set to 1).
    /// @param answer The answer bytes32.
    /// @return True if invalid, false otherwise.
    function isInvalid(bytes32 answer) public pure override returns (bool) {
        return (uint256(answer) == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    /// @dev Formats an array of outcome names into a JSON-like string for RealityETH.
    /// @param flatCFMQuestionParams The outcomes and other info.
    /// @return A formatted string for passing to RealityETH.
    function _formatDecisionQuestionParams(FlatCFMQuestionParams calldata flatCFMQuestionParams)
        private
        pure
        returns (string memory)
    {
        bytes memory formattedOutcomes = abi.encodePacked('"', flatCFMQuestionParams.outcomeNames[0], '"');
        for (uint256 i = 1; i < flatCFMQuestionParams.outcomeNames.length; i++) {
            formattedOutcomes = abi.encodePacked(formattedOutcomes, ',"', flatCFMQuestionParams.outcomeNames[i], '"');
        }
        return string(abi.encodePacked(formattedOutcomes));
    }

    /// @dev Formats a single outcome name string for RealityETH.
    /// @param outcomeName The outcome name to be formatted.
    /// @return A formatted string for passing to RealityETH.
    function _formatMetricQuestionParams(string memory outcomeName) private pure returns (string memory) {
        return string(abi.encodePacked(outcomeName));
    }

    /// @notice Internal function that checks if a question was already asked,
    ///         otherwise asks it on RealityETH with the specified parameters.
    /// @param templateId The question template ID on RealityETH.
    /// @param formattedQuestionParams The question text or data in JSON-like format.
    /// @param openingTime The time when the question becomes active.
    /// @return The question ID on RealityETH.
    function _askQuestion(uint256 templateId, string memory formattedQuestionParams, uint32 openingTime)
        private
        returns (bytes32)
    {
        // See RealityETH reference for how question IDs are derived.
        bytes32 contentHash = keccak256(abi.encodePacked(templateId, openingTime, formattedQuestionParams));
        bytes32 questionId = keccak256(
            abi.encodePacked(
                contentHash, arbitrator, questionTimeout, minBond, address(oracle), address(this), uint256(0)
            )
        );

        // If already asked, return existing questionId.
        if (oracle.getTimeout(questionId) != 0) {
            return questionId;
        }

        // Otherwise ask a new question with the provided parameters.
        return oracle.askQuestionWithMinBond(
            templateId, formattedQuestionParams, arbitrator, questionTimeout, openingTime, 0, minBond
        );
    }
}
