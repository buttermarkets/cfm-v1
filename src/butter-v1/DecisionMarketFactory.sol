// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "../Wrapped1155Factory.sol";
import "../ConditionalTokens.sol";
import "../FixedProductMarketMakerFactory.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./DecisionMarket.sol";
import "./QuestionTypes.sol";

contract DecisionMarketFactory {
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;
    //FixedProductMarketMakerFactory public immutable fixedProductMarketMakerFactory;
    Wrapped1155Factory public immutable wrapped1155Factory;

    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => CFMDecisionMarket) public markets;

    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        //FixedProductMarketMakerFactory _fixedProductMarketMakerFactory,
        Wrapped1155Factory _wrapped1155Factory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        //fixedProductMarketMakerFactory = _fixedProductMarketMakerFactory;
        wrapped1155Factory = _wrapped1155Factory;
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
        for (uint256 i = 0; i < _decisionQuestionParams.outcomeNames.length; i++) {
            // Must be <=25 to allow for -LONG & -SHORT suffixes
            require(bytes(_decisionQuestionParams.outcomeNames[i]).length <= 25, "outcome name too long");
        }

        markets[marketCount] = new CFMDecisionMarket(
            oracleAdapter,
            conditionalTokens,
            //fixedProductMarketMakerFactory,
            wrapped1155Factory,
            _collateralToken,
            _decisionQuestionParams,
            _conditionalQuestionParams
        );
        marketCount++;
    }
}
