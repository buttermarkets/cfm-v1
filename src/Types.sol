// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

/// @notice Parameters for a multi-outcome (decision) question.
struct FlatCFMQuestionParams {
    string[] outcomeNames;
    /// @dev Unix timestamp when the question opens.
    uint32 openingTime;
}

/// @notice Numeric range for a scalar (metric) question.
struct ScalarParams {
    uint256 minValue;
    uint256 maxValue;
}

/// @notice Parameters for a generic scalar question, including its opening time.
struct GenericScalarQuestionParams {
    ScalarParams scalarParams;
    /// @dev Unix timestamp when the question opens.
    uint32 openingTime;
}

/// @notice Conditional Tokens params of a conditional market.
struct ConditionalScalarCTParams {
    bytes32 questionId;
    bytes32 conditionId;
    bytes32 parentCollectionId;
    IERC20 collateralToken;
}

/// @notice Data for wrapped short/long/invalid token positions (3 outcomes).
struct WrappedConditionalTokensData {
    /// @dev ABI-encoded constructor name, symbol, decimals.
    bytes shortData;
    bytes longData;
    bytes invalidData;
    /// @dev Conditional Tokens position ids.
    uint256 shortPositionId;
    uint256 longPositionId;
    uint256 invalidPositionId;
    /// @dev ERC20s.
    IERC20 wrappedShort;
    IERC20 wrappedLong;
    IERC20 wrappedInvalid;
}

/// @notice Data for wrapped short/long token positions (2 outcomes).
struct InvalidlessWrappedConditionalTokensData {
    /// @dev ABI-encoded constructor name, symbol, decimals.
    bytes shortData;
    bytes longData;
    /// @dev Conditional Tokens position ids.
    uint256 shortPositionId;
    uint256 longPositionId;
    /// @dev ERC20s.
    IERC20 wrappedShort;
    IERC20 wrappedLong;
}
