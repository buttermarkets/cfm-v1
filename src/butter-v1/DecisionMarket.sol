// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ConditionalScalarMarket.sol";
import {ICFMOracleAdapter} from "./interfaces/ICFMOracleAdapter.sol";
import "./interfaces/IDecisionMarket.sol";
import "../ConditionalTokens.sol";

// TODO this is more a Flat CFM than a Decision Market. Think about making this a bit
// more generic and Flat CFM being a special case. For now, how CFMDecisionQuestion is strcutured is
// specific to 'flat', and ConditionalQuestionParams is specific to 'funding markets'.
// => Say Decision{,Question} (but this needs to be potentially plural) and
// Conditional{,Question}. This should happen in an abstract DecisionMarket
// contract that is implemented by this one.
contract CFMDecisionMarket is IDecisionMarket {
    ICFMOracleAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    mapping(uint256 => ConditionalScalarMarket) public outcomes;
    uint256 public outcomeCount;
    bool public isResolved;

    // TODO: move side effects to factory?
    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        CFMDecisionQuestionParams memory _decisionQuestionParams,
        CFMConditionalQuestionParams memory _conditionalQuestionParams
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = ConditionalTokens(_conditionalTokens);

        // FIXME: how to make it so that the oracle returns an outcome from a
        // list of outcomes?
        // FIXME store decisionQuestionId and refactor resolve
        //bytes32 decisionQuestionParams =
        //    oracle.formatDecisionQuestionParams(_decisionQuestion.roundName, _decisionQuestion.outcomeNames);
        bytes32 decisionQuestionId = oracleAdapter.askDecisionQuestion(_decisionQuestionParams);
        //bytes32 decisionConditionId = deriveConditionId(decisionQuestionId);

        conditionalTokens.prepareCondition(
            address(oracleAdapter), decisionQuestionId, _decisionQuestionParams.outcomeNames.length
        );

        for (uint256 i = 0; i < _decisionQuestionParams.outcomeNames.length; i++) {
            outcomes[outcomeCount] = new ConditionalScalarMarket(
                oracleAdapter, conditionalTokens, _conditionalQuestionParams, _decisionQuestionParams.outcomeNames[i]
            );
            outcomeCount++;
        }
    }

    // Process for a resolver: call submitAnswer on Reality then resolve here
    // FIXME: no arguments needed
    function resolve(bytes32 decisionQuestionId, uint256 numOutcomes) external {
        // TODO Validate questionID
        uint256 answer = uint256(oracleAdapter.resultForOnceSettled(decisionQuestionId));
        uint256[] memory payouts = new uint256[](numOutcomes + 1);

        if (answer == uint256(oracleAdapter.getInvalidValue())) {
            // FIXME: remove the INVALID_RESULT case
            // the last outcome is INVALID_RESULT.
            payouts[numOutcomes] = 1;
        } else {
            bool allZeroes = true;

            for (uint256 i = 0; i < numOutcomes; i++) {
                payouts[i] = (answer >> i) & 1;
                allZeroes = allZeroes && payouts[i] == 0;
            }

            if (allZeroes) {
                // invalid result.
                payouts[numOutcomes] = 1;
            }
        }

        conditionalTokens.reportPayouts(decisionQuestionId, payouts);
    }

    function getResolved() public view returns (bool) {
        return isResolved;
    }

    //function deriveConditionId(uint256 decisionQuestionId) private view returns (bytes32) {
    //    return keccak256(abi.encode(decisionQuestionId, address(_oracle), _decisionQuestion.outcomeNames.length));
    //}
}
