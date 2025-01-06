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
    string private constant SEPARATOR = "\u241f";

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

    function reportDecisionPayouts(IConditionalTokens conditionalTokens, bytes32 questionId, uint256 outcomeCount)
        external
        override
    {
        bytes32 answer = getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount + 1);
        uint256 numericAnswer = uint256(answer);

        if (isInvalid(answer) || numericAnswer == 0) {
            payouts[outcomeCount] = 1;
        } else {
            for (uint256 i = 0; i < outcomeCount; i++) {
                payouts[i] = (numericAnswer >> i) & 1;
            }
        }
        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function reportMetricPayouts(
        IConditionalTokens conditionalTokens,
        bytes32 questionId,
        uint256 minValue,
        uint256 maxValue
    ) external override {
        bytes32 answer = getAnswer(questionId);
        uint256[] memory payouts = new uint256[](3);
        uint256 numericAnswer = uint256(answer);

        if (isInvalid(answer)) {
            payouts[2] = 1;
        } else {
            if (numericAnswer <= minValue) {
                payouts[0] = 1;
            } else if (numericAnswer >= maxValue) {
                payouts[1] = 1;
            } else {
                payouts[0] = maxValue - numericAnswer;
                payouts[1] = numericAnswer - minValue;
            }
        }

        // `reportPayouts` requires that the condition is already prepared and
        // payouts aren't reported yet.
        conditionalTokens.reportPayouts(questionId, payouts);
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
