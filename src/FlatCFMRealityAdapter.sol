// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";
import "./FlatCFMOracleAdapter.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

// The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

// Formatting functions and template ids are coupled naturally. But we
// could decouple other attributes, if we expect templates to change more often
// than these.
contract FlatCFMRealityAdapter is FlatCFMOracleAdapter {
    string private constant SEPARATOR = "\u241f";

    IRealityETH public immutable oracle;
    address public immutable arbitrator;
    uint32 public immutable questionTimeout;
    uint256 public immutable minBond;

    constructor(IRealityETH _oracle, address _arbitrator, uint32 _questionTimeout, uint256 _minBond) {
        oracle = _oracle;
        arbitrator = _arbitrator;
        questionTimeout = _questionTimeout;
        minBond = _minBond;
    }

    // TODO unit test
    function _formatDecisionQuestionParams(FlatCFMQuestionParams calldata flatCFMQuestionParams)
        private
        pure
        returns (string memory)
    {
        bytes memory formattedOutcomes = abi.encodePacked('"', flatCFMQuestionParams.outcomeNames[0], '"');

        for (uint256 i = 1; i < flatCFMQuestionParams.outcomeNames.length; i++) {
            formattedOutcomes = abi.encodePacked(formattedOutcomes, ',"', flatCFMQuestionParams.outcomeNames[i], '"');
        }

        return string(abi.encodePacked(flatCFMQuestionParams.roundName, SEPARATOR, formattedOutcomes));
    }

    function _formatMetricQuestionParams(
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) private pure returns (string memory) {
        return string(
            abi.encodePacked(
                genericScalarQuestionParams.metricName,
                SEPARATOR,
                outcomeName,
                SEPARATOR,
                genericScalarQuestionParams.startDate,
                SEPARATOR,
                genericScalarQuestionParams.endDate
            )
        );
    }

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

    function askDecisionQuestion(uint256 decisionTemplateId, FlatCFMQuestionParams calldata flatCFMQuestionParams)
        public
        override
        returns (bytes32)
    {
        string memory formattedDecisionQuestionParams = _formatDecisionQuestionParams(flatCFMQuestionParams);
        return _askQuestion(decisionTemplateId, formattedDecisionQuestionParams, flatCFMQuestionParams.openingTime);
    }

    function askMetricQuestion(
        uint256 metricTemplateId,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        string memory outcomeName
    ) public override returns (bytes32) {
        string memory formattedMetricQuestionParams =
            _formatMetricQuestionParams(genericScalarQuestionParams, outcomeName);
        return _askQuestion(metricTemplateId, formattedMetricQuestionParams, genericScalarQuestionParams.openingTime);
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
