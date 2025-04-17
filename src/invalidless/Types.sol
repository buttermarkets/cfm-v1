// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

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
