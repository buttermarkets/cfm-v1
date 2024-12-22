// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";
import "./FlatCFMOracleAdapter.sol";
import {FlatCFMQuestionParams, ScalarQuestionParams} from "./QuestionTypes.sol";

// The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

// Formatting functions and template ids are coupled naturally. But we
// could decouple other attributes, if we expect templates to change more often
// than these.
contract FlatCFMRealityAdapter is FlatCFMOracleAdapter {
    string private constant SEPARATOR = "\u241f";

    IRealityETH public immutable oracle;
    address public immutable arbitrator;
    uint256 public immutable decisionTemplateId;
    uint256 public immutable metricTemplateId;
    uint32 public immutable questionTimeout;
    uint256 public immutable minBond;

    constructor(
        IRealityETH _oracle,
        address _arbitrator,
        uint256 _decisionTemplateId,
        uint256 _metricTemplateId,
        uint32 _questionTimeout,
        uint256 _minBond
    ) {
        oracle = _oracle;
        arbitrator = _arbitrator;
        decisionTemplateId = _decisionTemplateId;
        metricTemplateId = _metricTemplateId;
        questionTimeout = _questionTimeout;
        minBond = _minBond;
    }

    // TODO unit test
    function _formatDecisionQuestionParams(FlatCFMQuestionParams calldata decisionQuestionParams)
        private
        pure
        returns (string memory)
    {
        bytes memory formattedOutcomes = abi.encodePacked('"', decisionQuestionParams.outcomeNames[0], '"');

        for (uint256 i = 1; i < decisionQuestionParams.outcomeNames.length; i++) {
            formattedOutcomes = abi.encodePacked(formattedOutcomes, ',"', decisionQuestionParams.outcomeNames[i], '"');
        }

        return string(abi.encodePacked(decisionQuestionParams.roundName, SEPARATOR, formattedOutcomes));
    }

    function _formatMetricQuestionParams(
        ScalarQuestionParams calldata conditionalQuestionParams,
        string memory outcomeName
    ) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                conditionalQuestionParams.metricName,
                SEPARATOR,
                outcomeName,
                SEPARATOR,
                conditionalQuestionParams.startDate,
                SEPARATOR,
                conditionalQuestionParams.endDate
            )
        );
    }

    /// @dev This is the only function known by higher level contracts.
    /// @return The ID of the newly created Reality question.
    function _askQuestion(
        uint256 templateId,
        string memory formattedQuestionParams, // output of formatQuestionParams
        uint32 openingTime
    ) private returns (bytes32) {
        bytes32 content_hash = keccak256(abi.encodePacked(templateId, openingTime, formattedQuestionParams));

        bytes32 question_id = keccak256(
            abi.encodePacked(
                content_hash, arbitrator, questionTimeout, minBond, address(oracle), address(this), uint256(0)
            )
        );

        if (oracle.getTimeout(question_id) != 0) {
            return question_id;
        }

        /// @dev This would need to call UMA if we used UMA.
        return oracle.askQuestionWithMinBond(
            templateId, formattedQuestionParams, arbitrator, questionTimeout, openingTime, 0, minBond
        );
    }

    function askDecisionQuestion(FlatCFMQuestionParams calldata decisionQuestionParams)
        public
        override
        returns (bytes32)
    {
        string memory formattedDecisionQuestionParams = _formatDecisionQuestionParams(decisionQuestionParams);
        return _askQuestion(decisionTemplateId, formattedDecisionQuestionParams, decisionQuestionParams.openingTime);
    }

    function askMetricQuestion(ScalarQuestionParams calldata conditionalQuestionParams, string memory outcomeName)
        public
        override
        returns (bytes32)
    {
        string memory formattedMetricQuestionParams =
            _formatMetricQuestionParams(conditionalQuestionParams, outcomeName);
        return _askQuestion(metricTemplateId, formattedMetricQuestionParams, conditionalQuestionParams.openingTime);
    }

    /// @dev This is not-reverting only when the question is finalized in Reality.
    // TODO: QA the functioning of this.
    function getAnswer(bytes32 questionID) public view override returns (bytes32) {
        return oracle.resultForOnceSettled(questionID);
    }

    function isInvalid(bytes32 answer) public pure override returns (bool) {
        return (uint256(answer) == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }
}
