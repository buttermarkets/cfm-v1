// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO: use explicit imports whenever clearer.
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./QuestionTypes.sol";
import "./interfaces/ICFMOracleAdapter.sol";
import "./interfaces/IConditionalMarket.sol";
import "../ConditionalTokens.sol";
import "../FixedProductMarketMakerFactory.sol";
import "../FixedProductMarketMaker.sol";

contract ConditionalScalarMarket is IConditionalMarket {
    ICFMOracleAdapter public immutable oracleAdapter;
    ConditionalTokens public immutable conditionalTokens;
    bytes32 public immutable questionId;
    uint256 public immutable minValue;
    uint256 public immutable maxValue;
    FixedProductMarketMaker public immutable amm;

    bool public isResolved;

    constructor(
        ICFMOracleAdapter _oracleAdapter,
        ConditionalTokens _conditionalTokens,
        FixedProductMarketMakerFactory _fixedProductMarketMakerFactory,
        IERC20 _collateralToken,
        CFMConditionalQuestionParams memory _conditionalQuestionParams,
        string memory _outcomeName
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        minValue = _conditionalQuestionParams.minValue;
        maxValue = _conditionalQuestionParams.maxValue;

        questionId = oracleAdapter.askMetricQuestion(_conditionalQuestionParams, _outcomeName);

        conditionalTokens.prepareCondition(address(oracleAdapter), questionId, 2);
        bytes32 conditionId = conditionalTokens.getConditionId(address(oracleAdapter), questionId, 2);

        // XXX: wrap the position that corresponds to the single outcome with
        // `wrapped1155Factory`.
        // TODO:
        amm = _fixedProductMarketMakerFactory.createFixedProductMarketMaker(conditionalTokens, , [conditionId], 0);
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
}
