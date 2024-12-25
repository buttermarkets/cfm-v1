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

    event FlatCFMCreated(
        address indexed market, string roundName, address collateralToken, bytes32 questionId, bytes32 conditionId
    );
    event ConditionalMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex, address collateralToken
    );
    /*,
        bytes32 questionId,
        bytes32 conditionId*/

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
    ) external returns (FlatCFM) {
        uint256 outcomeCount = _flatCFMQuestionParams.outcomeNames.length;
        for (uint256 i = 0; i < outcomeCount; i++) {
            // Must be <=25 to allow for -LONG & -SHORT suffixes
            require(bytes(_flatCFMQuestionParams.outcomeNames[i]).length <= 25, "outcome name too long");
        }

        // 1. Ask decision market question.
        bytes32 cfmQuestionId = oracleAdapter.askDecisionQuestion(_flatCFMQuestionParams);

        // 2. Prepare ConditionalTokens condition.
        conditionalTokens.prepareCondition(address(oracleAdapter), cfmQuestionId, outcomeCount);
        bytes32 cfmConditionId = conditionalTokens.getConditionId(address(oracleAdapter), cfmQuestionId, outcomeCount);

        // 3. Deploy FlatCFM.
        FlatCFM flatCFM = new FlatCFM(oracleAdapter, conditionalTokens, outcomeCount, cfmQuestionId, cfmConditionId);

        emit FlatCFMCreated(
            address(flatCFM), _flatCFMQuestionParams.roundName, address(_collateralToken), cfmQuestionId, cfmConditionId
        );

        // 4. Deploy nested conditional markets.
        for (uint256 i = 0; i < outcomeCount; i++) {
            ConditionalScalarMarket csm = new ConditionalScalarMarket(
                oracleAdapter,
                conditionalTokens,
                wrapped1155Factory,
                _scalarQuestionParams,
                ConditionalTokensParams({
                    parentConditionId: cfmConditionId,
                    outcomeName: _flatCFMQuestionParams.outcomeNames[i],
                    outcomeIndex: i,
                    collateralToken: _collateralToken
                })
            );

            emit ConditionalMarketCreated(
                address(flatCFM),
                address(csm),
                i,
                address(_collateralToken) /*, conditionalQuestionId, conditionalConditionId*/
            );
        }

        return flatCFM;
    }
}
