// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

struct FlatCFMQuestionParams {
    string roundName;
    string[] outcomeNames;
    uint32 openingTime;
}

struct ScalarQuestionParams {
    string metricName;
    string startDate;
    string endDate; // Should be before openingTime.
    uint256 minValue;
    uint256 maxValue;
    uint32 openingTime;
}

struct ConditionalTokensParams {
    bytes32 parentConditionId;
    string outcomeName;
    uint256 outcomeIndex;
    IERC20 collateralToken;
}
