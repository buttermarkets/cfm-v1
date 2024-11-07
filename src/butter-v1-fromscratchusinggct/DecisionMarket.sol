// DecisionMarket.sol
pragma solidity ^0.8.0;

import "./ConditionalScalarMarket.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMarket.sol";
import "../ConditionalTokens.sol";

contract DecisionMarket is IMarket {
    IOracle public oracle;
    ConditionalTokens public conditionalTokens;
    mapping(uint256 => ConditionalScalarMarket) public outcomes;
    uint256 public outcomeCount;
    string public question;
    ScalarQuestion childQuestion;
    bool public isResolved;

    constructor(
        IOracle _oracle,
        ConditionalTokens _conditionalTokens,
        MultiCategoricalQuestion memory _decisionMarketQuestion,
        ScalarQuestion memory _childQuestion
    ) {
        oracle = _oracle;
        conditionalTokens = ConditionalTokens(_conditionalTokens);
        childQuestion = _childQuestion;
        question = _decisionMarketQuestion.text;

        conditionalTokens.prepareCondition(
            address(oracle),
            keccak256(abi.encodePacked(oracle.encodeMultiCategoricalQuestion(_decisionMarketQuestion.text))),
            _decisionMarketQuestion.numberOfOutcomes
        );

        for (uint256 i = 0; i < _decisionMarketQuestion.numberOfOutcomes; i++) {
            ConditionalScalarMarket newMarket = new ConditionalScalarMarket(oracle, conditionalTokens, childQuestion);
            outcomes[outcomeCount] = newMarket;
            outcomeCount++;
        }
    }

    function resolve() external {}

    function getResolved() public view returns (bool) {
        return isResolved;
    }
}
