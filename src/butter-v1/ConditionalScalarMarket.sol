// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "./QuestionTypes.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IMarket.sol";
import "../ConditionalTokens.sol";

contract ConditionalScalarMarket is IMarket {
    string public marketName;
    uint256[2] public outcomes;
    IOracle public immutable oracle;
    ConditionalTokens public immutable conditionalTokens;
    ScalarQuestion question;

    bool public isResolved;

    constructor(IOracle _oracle, ConditionalTokens _conditionalTokens, ScalarQuestion memory _question, string memory _parentConditionName) {
        oracle = _oracle;
        conditionalTokens = _conditionalTokens;

        question = _question;
        outcomes[0] = _question.lowerBound;
        outcomes[1] = _question.upperBound;

        conditionalTokens.prepareCondition(
            address(oracle), keccak256(abi.encode(oracle.encodeScalarQuestion(_question.text, _parentConditionName))), outcomes.length
        );

        //oracle.prepareQuestion();
    }

    function resolve(bytes32 questionId, uint256 low, uint256 high) external {
        // TODO Validate questionID
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](3);

        if (answer == uint256(oracle.getInvalidValue())) {
            // the last outcome is INVALID_RESULT.
            payouts[2] = 1;
        } else if (answer <= low) {
            payouts[0] = 1;
        } else if (answer >= high) {
            payouts[1] = 1;
        } else {
            payouts[0] = high - answer;
            payouts[1] = answer - low;
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function getResolved() public view returns (bool) {
        return isResolved;
    }
}
