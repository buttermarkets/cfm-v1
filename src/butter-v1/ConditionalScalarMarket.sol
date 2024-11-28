// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO: use explicit imports
import "@openzeppelin-contracts-5.0.2/token/ERC20/IERC20.sol";
import "./QuestionTypes.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./interfaces/IDecisionMarket.sol";
import "../ConditionalTokens.sol";

contract ConditionalScalarMarket is IDecisionMarket {
    string public marketName;
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;

    bool public isResolved;

    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        CFMConditionalQuestionParams memory _conditionalQuestionParams,
        string memory _outcomeName
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;

        bytes32 metricQuestionId = oracleAdapter.askMetricQuestion(_conditionalQuestionParams, _outcomeName);

        conditionalTokens.prepareCondition(address(oracleAdapter), metricQuestionId, 2);

        // TODO: This would call FixedProductMarketMakerFactory
    }

    // FIXME: arguments aren't needed
    function resolve(bytes32 questionId, uint256 low, uint256 high) external {
        uint256 answer = uint256(oracleAdapter.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](3);

        if (answer == uint256(oracleAdapter.getInvalidValue())) {
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

    //function deriveConditionId(uint256 conditionalQuestionId) private view returns (bytes32) {
    //    return keccak256(abi.encode(conditionalQuestionId, address(oracle), question.minValue, question.maxValue));
    //}
}
