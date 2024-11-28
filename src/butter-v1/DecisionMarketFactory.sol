// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DecisionMarket.sol";
import "../ConditionalTokens.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./QuestionTypes.sol";

contract DecisionMarketFactory {
    ICFMOracleAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => CFMDecisionMarket) public markets;

    constructor(ICFMOracleAdapter _oracleAdapter, ConditionalTokens _conditionalTokens) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
    }

    // This could expect and parameters. But this would create tight coupling
    // with Reality.
    // Another approach is to make OracleAdapter plug into different templates
    // (or redeploy different OracleAdapter when not happy with the template.
    function createMarket(
        CFMDecisionQuestionParams calldata _decisionQuestionParams,
        CFMConditionalQuestionParams calldata _conditionalQuestionParams
    ) external {
        markets[marketCount] =
            new CFMDecisionMarket(oracleAdapter, conditionalTokens, _decisionQuestionParams, _conditionalQuestionParams);
        marketCount++;
    }
}
