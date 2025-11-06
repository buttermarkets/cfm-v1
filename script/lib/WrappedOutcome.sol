// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {String31} from "src/libs/String31.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";

/// @title WrappedOutcome
/// @notice Library for creating wrapped ERC20 tokens from conditional token positions
/// @dev Uses "IF-" prefix convention for outcome token names
library WrappedOutcome {
    using String31 for string;

    /// @notice Creates ERC20 token metadata for a wrapped outcome token
    /// @dev Token name and symbol are both set to "IF-{outcomeName}"
    /// @param outcomeName Base name for the outcome (e.g., "Sky")
    /// @param decimals Decimals for the wrapped token (typically from collateral)
    /// @return data Encoded bytes for Wrapped1155Factory containing name, symbol, and decimals
    function outcomeErc20Data(string memory outcomeName, uint8 decimals) internal pure returns (bytes memory data) {
        string memory tokenName = string.concat("IF-", outcomeName);
        data = abi.encodePacked(tokenName.toString31(), tokenName.toString31(), decimals);
    }

    /// @notice Ensures wrapped token exists for a position, creating if necessary
    /// @dev Calls Wrapped1155Factory.requireWrapped1155 with generated metadata
    /// @param wrapped1155Factory The factory to use for wrapping
    /// @param conditionalTokens The conditional tokens contract
    /// @param positionId The position ID to wrap
    /// @param outcomeName The outcome name (will be prefixed with "IF-")
    /// @param collateralToken The collateral token (used to get decimals)
    /// @return wrappedToken The wrapped ERC20 token (created or existing)
    function requireWrappedOutcome(
        IWrapped1155Factory wrapped1155Factory,
        IConditionalTokens conditionalTokens,
        uint256 positionId,
        string memory outcomeName,
        IERC20 collateralToken
    ) internal returns (IERC20 wrappedToken) {
        uint8 decimals = IERC20Metadata(address(collateralToken)).decimals();
        bytes memory data = outcomeErc20Data(outcomeName, decimals);
        wrappedToken = wrapped1155Factory.requireWrapped1155(conditionalTokens, positionId, data);
    }
}
