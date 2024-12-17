// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
// TODO: rename Types.

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

struct CFMDecisionQuestionParams {
    string roundName;
    string[] outcomeNames;
    uint32 openingTime;
}

struct CFMConditionalQuestionParams {
    string metricName;
    string startDate;
    string endDate; // Should be before openingTime.
    uint256 minValue;
    uint256 maxValue;
    uint32 openingTime;
}

struct ConditionalMarketCTParams {
    bytes32 parentConditionId;
    string outcomeName;
    uint256 outcomeIndex;
    IERC20 collateralToken;
}
