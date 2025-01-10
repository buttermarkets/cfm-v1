// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";

import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

// The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

// Formatting functions and template ids are coupled naturally. But we
// could decouple other attributes, if we expect templates to change more often
// than these.
contract FlatCFMRealityAdapter is FlatCFMOracleAdapter {
    string public constant SEPARATOR = "\u241f";

    IRealityETH public immutable oracle;
    address public immutable arbitrator;
    uint32 public immutable questionTimeout;
    uint256 public immutable minBond;

    error QuestionStuck(address questionId);

    constructor(IRealityETH _oracle, address _arbitrator, uint32 _questionTimeout, uint256 _minBond) {
        oracle = _oracle;
        arbitrator = _arbitrator;
        questionTimeout = _questionTimeout;
        minBond = _minBond;
    }

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

    function _formatMetricQuestionParams(string memory outcomeName) private pure returns (string memory) {
        return string(abi.encodePacked(outcomeName));
    }

    /// @notice Looks up if there is an existing Reality question, otherwise
    ///     creates one.
    /// @return The Reality question ID.
    function _askQuestion(
        uint256 templateId,
        string memory formattedQuestionParams, // output of formatQuestionParams
        uint32 openingTime
    ) private returns (bytes32) {
        // solhint-disable-next-line
        // See https://github.com/RealityETH/reality-eth-monorepo/blob/13f0556b72059e4a4d402fd75999d2ce320bd3c4/packages/contracts/flat/RealityETH-3.0.sol#L324
        bytes32 contentHash = keccak256(abi.encodePacked(templateId, openingTime, formattedQuestionParams));
        bytes32 questionId = keccak256(
            abi.encodePacked(
                contentHash, arbitrator, questionTimeout, minBond, address(oracle), address(this), uint256(0)
            )
        );

        if (oracle.getTimeout(questionId) != 0) {
            return questionId;
        }

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
        string memory formattedMetricQuestionParams = _formatMetricQuestionParams(outcomeName);
        return _askQuestion(metricTemplateId, formattedMetricQuestionParams, genericScalarQuestionParams.openingTime);
    }

    /// @dev `resultForOnceSettled` reverts if the question is not finalized.
    ///     When the Reality question is answered "too soon", the reopnened
    ///     question's result is returned (or raises if not finalized either).
    // solhint-disable-next-line max-line-length
    ///     See https://github.com/RealityETH/reality-eth-monorepo/blob/13f0556b72059e4a4d402fd75999d2ce320bd3c4/packages/contracts/flat/RealityETH-3.0.sol#L618C14-L618C34
    function getAnswer(bytes32 questionId) public view override returns (bytes32) {
        return oracle.resultForOnceSettled(questionId);
    }

    function isInvalid(bytes32 answer) public pure override returns (bool) {
        return (uint256(answer) == 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }
}
