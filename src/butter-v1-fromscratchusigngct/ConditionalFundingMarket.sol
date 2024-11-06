// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "./QuestionType.sol";
import "./OracleAdapter.sol";
import "../ConditionalTokens.sol";

contract ConditionalFundingMarket {
    string public marketName; // Making this immutable makes sense to me.
    QuestionType public immutable parentConditionType; // Can be categorical or multi-categorical.
    QuestionType public immutable conditionType = QuestionType.Scalar; // This is always a scalar market.
    uint256 public lowerBound;
    uint256 public upperBound;

    OracleAdapter public immutable oracle;
    ConditionalTokens public immutable conditionalTokens;

    /// @dev Constructor
    /// @param _parentConditionType The type of condition this market represents
    /// @param _conditionalTokens The ConditionalTokens contract address
    constructor(
        OracleAdapter _oracle,
        ConditionalTokens _conditionalTokens,
        QuestionType _parentConditionType,
        uint256 _lowerBound,
        uint256 _upperBound
    ) {
        oracle = _oracle;
        conditionalTokens = _conditionalTokens;
        parentConditionType = _parentConditionType;
        lowerBound = _lowerBound;
        upperBound = _upperBound;

        // Prepare condition with 2 outcomes (UP/DOWN)
        bytes32 questionId =
            keccak256(abi.encodePacked(encodeRealityQuestionWithoutOutcomes("Will the price go up?", "finance", "en")));
        uint256 outcomeSlotCount = 2; // 2 because it's scalar
        conditionalTokens.prepareCondition(address(oracle), questionId, outcomeSlotCount);
    }

    /// @dev Encodes the question, category and language following the Reality structure.
    /// If any parameter has a special character like quotes, it must be properly escaped.
    /// @param question The question text.
    /// @param category The question category.
    /// @param lang The question language.
    /// @return The encoded question.
    function encodeRealityQuestionWithoutOutcomes(string memory question, string memory category, string memory lang)
        internal
        pure
        returns (string memory)
    {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        return string(abi.encodePacked(question, separator, category, separator, lang));
    }
}
