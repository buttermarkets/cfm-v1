// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecisionMarket.sol";
import "../ConditionalTokens.sol";
import "./interfaces/IOracle.sol";
import "./QuestionTypes.sol";

contract DecisionMarketFactory {
    IOracle public oracle;
    ConditionalTokens public conditionalTokens;
    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => DecisionMarket) public markets;

    constructor(IOracle _oracle, ConditionalTokens _conditionalTokens) {
        oracle = _oracle;
        conditionalTokens = ConditionalTokens(_conditionalTokens);
    }

    // This could expect and parameters. But this would create tight coupling
    // with Reality.
    // Another approach is to make OracleAdapter plug into different templates
    // (or redeploy different OracleAdapter when not happy with the template.
    function createMarket(MultiCategoricalQuestion calldata _question, ScalarQuestion calldata _childQuestion)
        external
    {
        DecisionMarket newMarket = new DecisionMarket(oracle, conditionalTokens, _question, _childQuestion);
        markets[marketCount] = newMarket;
        marketCount++;
    }
}
