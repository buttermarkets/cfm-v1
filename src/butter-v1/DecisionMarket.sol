// DecisionMarket.sol
pragma solidity ^0.8.0;

import "./ConditionalScalarMarket.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMarket.sol";
import "../ConditionalTokens.sol";

contract DecisionMarket is IMarket {
    IOracle public oracle;
    ConditionalTokens public conditionalTokens;
    mapping(uint256 => ConditionalScalarMarket) public outcomes;
    uint256 public outcomeCount;
    string public question;
    ScalarQuestion childQuestion;
    bool public isResolved;

    constructor(
        IOracle _oracle,
        ConditionalTokens _conditionalTokens,
        MultiCategoricalQuestion memory _decisionMarketQuestion,
        ScalarQuestion memory _childQuestion
    ) {
        oracle = _oracle;
        conditionalTokens = ConditionalTokens(_conditionalTokens);
        childQuestion = _childQuestion;
        question = _decisionMarketQuestion.text;

        conditionalTokens.prepareCondition(
            address(oracle),
            keccak256(
                abi.encode(
                    oracle.encodeMultiCategoricalQuestion(
                        _decisionMarketQuestion.text, _decisionMarketQuestion.outcomes
                    )
                )
            ),
            _decisionMarketQuestion.outcomes.length
        );

        for (uint256 i = 0; i < _decisionMarketQuestion.outcomes.length; i++) {
            ConditionalScalarMarket newMarket = new ConditionalScalarMarket(
                oracle, conditionalTokens, childQuestion, _decisionMarketQuestion.outcomes[i]
            );
            outcomes[outcomeCount] = newMarket;
            outcomeCount++;
        }
    }

    function resolve(bytes32 questionId, uint256 numOutcomes) external {
        // TODO Validate questionID
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](numOutcomes + 1);

        if (answer == uint256(oracle.getInvalidValue())) {
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

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function getResolved() public view returns (bool) {
        return isResolved;
    }
}
