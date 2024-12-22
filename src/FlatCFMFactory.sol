// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";
import "./FlatCFM.sol";
import "./QuestionTypes.sol";

contract FlatCFMFactory {
    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    uint256 public marketCount;

    // Mapping from market ID to DecisionMarket contract
    mapping(uint256 => FlatCFM) public markets;

    constructor(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
    }

    function createMarket(
        FlatCFMQuestionParams calldata _flatCFMQuestionParams,
        ScalarQuestionParams calldata _scalarQuestionParams,
        IERC20 _collateralToken
    ) external {
        for (uint256 i = 0; i < _flatCFMQuestionParams.outcomeNames.length; i++) {
            // Must be <=25 to allow for -LONG & -SHORT suffixes
            require(bytes(_flatCFMQuestionParams.outcomeNames[i]).length <= 25, "outcome name too long");
        }

        markets[marketCount] = new FlatCFM(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            _collateralToken,
            _flatCFMQuestionParams,
            _scalarQuestionParams
        );
        marketCount++;
    }
}
