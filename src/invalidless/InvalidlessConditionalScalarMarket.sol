// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../interfaces/IWrapped1155Factory.sol";
import "../interfaces/IConditionalTokens.sol";
import {ScalarParams, ConditionalScalarCTParams} from "../Types.sol";
import "../FlatCFMOracleAdapter.sol";

import {InvalidlessWrappedConditionalTokensData} from "./Types.sol";

/// @title InvalidlessConditionalScalarMarket
/// @notice Creates a scalar (range-based) conditional market for a single outcome without an invalid state.
contract InvalidlessConditionalScalarMarket is ERC1155Holder {
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

    /// @notice Stores references to the wrapped positions for short/long.
    InvalidlessWrappedConditionalTokensData public wrappedCTData;

    /// @notice Default payouts to use if the oracle returns an invalid answer [short, long].
    uint256[2] public defaultInvalidPayouts;

    /// @dev Initialization guard.
    bool public initialized;

    error AlreadyInitialized();
    error WrappedShortTransferFailed();
    error WrappedLongTransferFailed();

    /// @notice Initializes a freshly cloned InvalidlessConditionalScalarMarket.
    /// @param _oracleAdapter Oracle adapter for answer resolution.
    /// @param _conditionalTokens The Gnosis Conditional Tokens contract address.
    /// @param _wrapped1155Factory Factory for wrapping/unwrapping ERC1155 positions.
    /// @param _conditionalScalarCTParams Condition Tokens data.
    /// @param _scalarParams Range for the scalar question.
    /// @param _wrappedCTData Wrapped Short/Long positions.
    /// @param _defaultInvalidPayouts Default payouts to use if the answer is invalid [short, long].
    function initialize(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory,
        ConditionalScalarCTParams memory _conditionalScalarCTParams,
        ScalarParams memory _scalarParams,
        InvalidlessWrappedConditionalTokensData memory _wrappedCTData,
        uint256[2] calldata _defaultInvalidPayouts
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
        ctParams = _conditionalScalarCTParams;
        scalarParams = _scalarParams;
        wrappedCTData = _wrappedCTData;
        defaultInvalidPayouts = _defaultInvalidPayouts;
    }

    /// @notice Resolves the scalar condition in the conditional tokens contract.
    /// @dev Allocates payouts to Short/Long based on final numeric value.
    ///      If the oracle returns an invalid value, uses the defaultInvalidPayouts.
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(ctParams.questionId);
        uint256[] memory payouts = new uint256[](2);

        if (oracleAdapter.isInvalid(answer)) {
            // Use default invalid payouts
            payouts[0] = defaultInvalidPayouts[0];
            payouts[1] = defaultInvalidPayouts[1];
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
