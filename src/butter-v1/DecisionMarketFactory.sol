// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./DecisionMarket.sol";
import "../ConditionalTokens.sol";
import "../FixedProductMarketMakerFactory.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./QuestionTypes.sol";

contract DecisionMarketFactory {
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;
    FixedProductMarketMakerFactory public immutable fixedProductMarketMakerFactory;

    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => CFMDecisionMarket) public markets;

    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        FixedProductMarketMakerFactory _fixedProductMarketMakerFactory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        fixedProductMarketMakerFactory = _fixedProductMarketMakerFactory;
    }

    // This could expect and parameters. But this would create tight coupling
    // with Reality.
    // Another approach is to make OracleAdapter plug into different templates
    // (or redeploy different OracleAdapter when not happy with the template.
    function createMarket(
        CFMDecisionQuestionParams calldata _decisionQuestionParams,
        CFMConditionalQuestionParams calldata _conditionalQuestionParams,
        IERC20 _collateralToken
    ) external {
        markets[marketCount] = new CFMDecisionMarket(
            oracleAdapter,
            conditionalTokens,
            fixedProductMarketMakerFactory,
            _collateralToken,
            _decisionQuestionParams,
            _conditionalQuestionParams
        );
        marketCount++;
    }
}
