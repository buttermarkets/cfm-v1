// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

struct FlatCFMQuestionParams {
    string roundName;
    string[] outcomeNames;
    uint32 openingTime;
}

struct ScalarParams {
    uint256 minValue;
    uint256 maxValue;
}

struct GenericScalarQuestionParams {
    string metricName;
    string startDate;
    string endDate; // Should be before openingTime.
    ScalarParams scalarParams;
    uint32 openingTime;
}

struct ConditionalScalarCTParams {
    bytes32 questionId;
    bytes32 conditionId;
    bytes32 parentCollectionId;
    IERC20 collateralToken;
}

struct WrappedConditionalTokensData {
    bytes shortData;
    bytes longData;
    uint256 shortPositionId;
    uint256 longPositionId;
    IERC20 wrappedShort;
    IERC20 wrappedLong;
}
