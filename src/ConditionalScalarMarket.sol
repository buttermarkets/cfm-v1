// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import {ScalarParams, ConditionalScalarCTParams, WrappedConditionalTokensData} from "./Types.sol";
import "./FlatCFMOracleAdapter.sol";

/// @title ConditionalScalarMarket
/// @notice Creates a scalar (range-based) conditional market for a single outcome.
contract ConditionalScalarMarket is ERC1155Holder {
    /// @notice Oracle adapter for scalar question resolution.
    FlatCFMOracleAdapter public oracleAdapter;

    /// @notice Gnosis Conditional Tokens contract.
    IConditionalTokens public conditionalTokens;

    /// @notice Factory for wrapping ERC1155 positions into ERC20s.
    IWrapped1155Factory public wrapped1155Factory;

    /// @notice Struct containing the Conditional Tokens parameters.
    ConditionalScalarCTParams public ctParams;

    /// @notice Defines the numeric range [minValue, maxValue] for the scalar outcome.
    ScalarParams public scalarParams;

    /// @notice Stores references to the wrapped positions for short/long/invalid.
    WrappedConditionalTokensData public wrappedCTData;

    /// @dev Initialization guard.
    bool public initialized;

    error AlreadyInitialized();
    error WrappedShortTransferFailed();
    error WrappedLongTransferFailed();
    error WrappedInvalidTransferFailed();

    /// @notice Initializes a freshly cloned ConditionalScalarMarket.
    /// @param _oracleAdapter Oracle adapter for answer resolution.
    /// @param _conditionalTokens The Gnosis Conditional Tokens contract address.
    /// @param _wrapped1155Factory Factory for wrapping/unwrapping ERC1155 positions.
    /// @param _conditionalScalarCTParams Condition Tokens data.
    /// @param _scalarParams Range for the scalar question.
    /// @param _wrappedCTData Wrapped Short/Long/Invalid positions.
    function initialize(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory,
        ConditionalScalarCTParams memory _conditionalScalarCTParams,
        ScalarParams memory _scalarParams,
        WrappedConditionalTokensData memory _wrappedCTData
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
        ctParams = _conditionalScalarCTParams;
        scalarParams = _scalarParams;
        wrappedCTData = _wrappedCTData;
    }

    /// @notice Resolves the scalar condition in the conditional tokens contract.
    /// @dev Allocates payouts to Short/Long/Invalid based on final numeric value.
    ///      The invalid outcome  gets the full payout if the oralce returns the
    ///      invalid value.
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(ctParams.questionId);
        uint256[] memory payouts = new uint256[](3);

        if (oracleAdapter.isInvalid(answer)) {
            // 'Invalid' outcome receives full payout
            payouts[2] = 1;
        } else {
            uint256 numericAnswer = uint256(answer);
            if (numericAnswer <= scalarParams.minValue) {
                payouts[0] = 1; // short
            } else if (numericAnswer >= scalarParams.maxValue) {
                payouts[1] = 1; // long
            } else {
                payouts[0] = scalarParams.maxValue - numericAnswer;
                payouts[1] = numericAnswer - scalarParams.minValue;
            }
        }
        conditionalTokens.reportPayouts(ctParams.questionId, payouts);
    }
}
