// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import "./CFMOracleAdapter.sol";
import "./CFMDecisionMarket.sol";
import "./QuestionTypes.sol";

contract DecisionMarketFactory {
    CFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => CFMDecisionMarket) public markets;

    constructor(
        CFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
    }

    function createMarket(
        CFMDecisionQuestionParams calldata _decisionQuestionParams,
        CFMConditionalQuestionParams calldata _conditionalQuestionParams,
        IERC20 _collateralToken
    ) external {
        for (uint256 i = 0; i < _decisionQuestionParams.outcomeNames.length; i++) {
            // Must be <=25 to allow for -LONG & -SHORT suffixes
            require(bytes(_decisionQuestionParams.outcomeNames[i]).length <= 25, "outcome name too long");
        }

        markets[marketCount] = new CFMDecisionMarket(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            _collateralToken,
            _decisionQuestionParams,
            _conditionalQuestionParams
        );
        marketCount++;
    }
}
