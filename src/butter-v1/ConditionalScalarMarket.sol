// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO: use explicit imports
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./QuestionTypes.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./interfaces/IDecisionMarket.sol";
import "../ConditionalTokens.sol";

contract ConditionalScalarMarket is IDecisionMarket {
    string public marketName;
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;
    bytes32 public immutable questionId;
    uint256 public immutable minValue;
    uint256 public immutable maxValue;

    bool public isResolved;

    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        CFMConditionalQuestionParams memory _conditionalQuestionParams,
        string memory _outcomeName
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        minValue = _conditionalQuestionParams.minValue;
        maxValue = _conditionalQuestionParams.maxValue;

        questionId = oracleAdapter.askMetricQuestion(_conditionalQuestionParams, _outcomeName);

        conditionalTokens.prepareCondition(address(oracleAdapter), questionId, 2);

        // TODO: This would call FixedProductMarketMakerFactory
    }

    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](3);

        // If the answer is invalid, no payouts are returned.
        // TODO: test all cases, including invalid. In invalid, the user should
        // still be able to merge positions.
        if (!oracleAdapter.isInvalid(answer)) {
            uint256 numericAnswer = uint256(answer);
            if (numericAnswer <= minValue) {
                payouts[0] = 1;
            } else if (numericAnswer >= maxValue) {
                payouts[1] = 1;
            } else {
                payouts[0] = maxValue - numericAnswer;
                payouts[1] = numericAnswer - minValue;
            }
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    function getResolved() public view returns (bool) {
        return isResolved;
    }

    //function deriveConditionId(uint256 conditionalQuestionId) private view returns (bytes32) {
    //    return keccak256(abi.encode(conditionalQuestionId, address(oracle), question.minValue, question.maxValue));
    //}
}
