// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IDecisionMarket.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "../ConditionalTokens.sol";
import "../FixedProductMarketMakerFactory.sol";
import "./ConditionalScalarMarket.sol";

// TODO this is more a Flat CFM than a Decision Market. Think about making this a bit
// more generic and Flat CFM being a special case. For now, how CFMDecisionQuestion is strcutured is
// specific to 'flat', and ConditionalQuestionParams is specific to 'funding markets'.
// => Say Decision{,Question} (but this needs to be potentially plural) and
// Conditional{,Question}. This should happen in an abstract DecisionMarket
// contract that is implemented by this one.
contract CFMDecisionMarket is IDecisionMarket {
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;
    FixedProductMarketMakerFactory public immutable fixedProductMarketMakerFactory;
    IERC20 public immutable collateralToken;
    bytes32 public immutable questionId;
    uint256 public immutable outcomeCount;

    mapping(uint256 => ConditionalScalarMarket) public outcomes;

    bool public isResolved;

    // TODO: move side effects to factory?
    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        FixedProductMarketMakerFactory _fixedProductMarketMakerFactory,
        IERC20 _collateralToken,
        CFMDecisionQuestionParams memory _decisionQuestionParams,
        CFMConditionalQuestionParams memory _conditionalQuestionParams
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = ConditionalTokens(_conditionalTokens);
        outcomeCount = _decisionQuestionParams.outcomeNames.length;

        questionId = oracleAdapter.askDecisionQuestion(_decisionQuestionParams);

        conditionalTokens.prepareCondition(address(oracleAdapter), questionId, outcomeCount);

        for (uint256 i = 0; i < outcomeCount; i++) {
            outcomes[i] = new ConditionalScalarMarket(
                oracleAdapter,
                conditionalTokens,
                _fixedProductMarketMakerFactory,
                _conditionalQuestionParams,
                _decisionQuestionParams.outcomeNames[i]
            );
        }
    }

    // Process for a resolver: call submitAnswer on Reality then resolve here
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount);

        // TODO: test!
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
