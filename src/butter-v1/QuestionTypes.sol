// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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
