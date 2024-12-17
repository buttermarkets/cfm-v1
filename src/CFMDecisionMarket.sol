// TODO: update license.
// SPDX-License-Identifier: GPL-3.0-or-later
// TODO: move everything to latest version
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import {CFMDecisionQuestionParams, CFMConditionalQuestionParams, ConditionalMarketCTParams} from "./QuestionTypes.sol";
import "./DecisionMarket.sol";
import "./CFMOracleAdapter.sol";
import "./ConditionalScalarMarket.sol";

// TODO this is more a Flat CFM than a Decision Market. Think about making this a bit
// more generic and Flat CFM being a special case. For now, how CFMDecisionQuestion is strcutured is
// specific to 'flat', and ConditionalQuestionParams is specific to 'funding markets'.
// => Say Decision{,Question} (but this needs to be potentially plural) and
// Conditional{,Question}. This should happen in an abstract DecisionMarket
// contract that is implemented by this one.
contract CFMDecisionMarket is DecisionMarket {
    CFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    // `questionId` and `outcomeCount` are recorded at construction, then
    // used to resolve the market.
    bytes32 public immutable questionId;
    uint256 public immutable outcomeCount;
    bytes32 public immutable conditionId;

    mapping(uint256 => ConditionalScalarMarket) public outcomes;

    bool public isResolved;

    // TODO: move side effects to factory
    constructor(
        CFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        //FixedProductMarketMakerFactory _fixedProductMarketMakerFactory,
        IWrapped1155Factory _wrapped1155Factory,
        IERC20 _collateralToken,
        CFMDecisionQuestionParams memory _decisionQuestionParams,
        CFMConditionalQuestionParams memory _conditionalQuestionParams
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = IConditionalTokens(_conditionalTokens);
        outcomeCount = _decisionQuestionParams.outcomeNames.length;

        questionId = oracleAdapter.askDecisionQuestion(_decisionQuestionParams);

        conditionalTokens.prepareCondition(address(oracleAdapter), questionId, outcomeCount);
        conditionId = conditionalTokens.getConditionId(address(oracleAdapter), questionId, outcomeCount);

        // Deploy nested conditional markets.
        for (uint256 i = 0; i < outcomeCount; i++) {
            outcomes[i] = new ConditionalScalarMarket(
                oracleAdapter,
                conditionalTokens,
                //_fixedProductMarketMakerFactory,
                _wrapped1155Factory,
                _conditionalQuestionParams,
                ConditionalMarketCTParams({
                    parentConditionId: conditionId,
                    outcomeName: _decisionQuestionParams.outcomeNames[i],
                    outcomeIndex: i,
                    collateralToken: _collateralToken
                })
            );
        }
    }

    // Process for a resolver: call submitAnswer on Reality then resolve here
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount);

        // TODO: test the invalid case.
        if (!oracleAdapter.isInvalid(answer)) {
            uint256 numericAnswer = uint256(answer);

            for (uint256 i = 0; i < outcomeCount; i++) {
                payouts[i] = (numericAnswer >> i) & 1;
            }
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }
}
