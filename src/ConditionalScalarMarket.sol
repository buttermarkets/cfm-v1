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

    /// @notice Splits "decision outcome" ERC1155 into short/long/invalid ERC20s.
    /// @dev Burns the user’s decision outcome tokens, mints short/long/invalid ERC1155,
    ///      then wraps them into ERC20 and transfers to the user.
    /// @param amount Number of decision outcome tokens to split.
    function split(uint256 amount) external {
        // User transfers decision outcome ERC1155 to this contract.
        conditionalTokens.safeTransferFrom(
            msg.sender,
            address(this),
            conditionalTokens.getPositionId(ctParams.collateralToken, ctParams.parentCollectionId),
            amount,
            ""
        );

        // Split position. Decision outcome ERC1155 are burnt. Conditional
        // Short/Long/Invalid ERC1155 are minted to the contract.
        conditionalTokens.splitPosition(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, _discreetPartition(), amount
        );

        // Contract transfers Short/Long/Invalid ERC1155 to wrapped1155Factory and
        // gets back Short/Long/Invalid ERC20.
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), wrappedCTData.shortPositionId, amount, wrappedCTData.shortData
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), wrappedCTData.longPositionId, amount, wrappedCTData.longData
        );
        conditionalTokens.safeTransferFrom(
            address(this),
            address(wrapped1155Factory),
            wrappedCTData.invalidPositionId,
            amount,
            wrappedCTData.invalidData
        );

        // Contract transfers Short/Long/Invalid ERC20 to user.
        if (!wrappedCTData.wrappedShort.transfer(msg.sender, amount)) {
            revert WrappedShortTransferFailed();
        }
        if (!wrappedCTData.wrappedLong.transfer(msg.sender, amount)) {
            revert WrappedLongTransferFailed();
        }
        if (!wrappedCTData.wrappedInvalid.transfer(msg.sender, amount)) {
            revert WrappedInvalidTransferFailed();
        }
    }

    /// @notice Merges short/long/invalid ERC20 back into a single "decision outcome" ERC1155.
    /// @param amount Quantity of each short/long/invalid token to merge.
    function merge(uint256 amount) external {
        // User transfers Short/Long/Invalid ERC20 to contract.
        if (!wrappedCTData.wrappedShort.transferFrom(msg.sender, address(this), amount)) {
            revert WrappedShortTransferFailed();
        }
        if (!wrappedCTData.wrappedLong.transferFrom(msg.sender, address(this), amount)) {
            revert WrappedLongTransferFailed();
        }
        if (!wrappedCTData.wrappedInvalid.transferFrom(msg.sender, address(this), amount)) {
            revert WrappedInvalidTransferFailed();
        }

        // Contract transfers Short/Long/Invalid ERC20 to wrapped1155Factory and gets
        // back Short/Long/Invalid ERC1155.
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.shortPositionId, amount, address(this), wrappedCTData.shortData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.longPositionId, amount, address(this), wrappedCTData.longData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.invalidPositionId, amount, address(this), wrappedCTData.invalidData
        );

        // Merge position. Short/Long/Invalid ERC1155 are burnt. Decision outcome
        // ERC1155 are minted.
        conditionalTokens.mergePositions(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, _discreetPartition(), amount
        );

        // Contract transfers decision outcome ERC1155 to user.
        conditionalTokens.safeTransferFrom(
            address(this),
            msg.sender,
            conditionalTokens.getPositionId(ctParams.collateralToken, ctParams.parentCollectionId),
            amount,
            ""
        );
    }

    /// @notice Redeems short/long/invalid tokens for collateral after resolution.
    /// @param shortAmount The amount of Short tokens to redeem.
    /// @param longAmount The amount of Long tokens to redeem.
    /// @param invalidAmount The amount of Invalid tokens to redeem.
    function redeem(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) external {
        // User transfers Short/Long/Invalid ERC20 to contract.
        if (!wrappedCTData.wrappedShort.transferFrom(msg.sender, address(this), shortAmount)) {
            revert WrappedShortTransferFailed();
        }
        if (!wrappedCTData.wrappedLong.transferFrom(msg.sender, address(this), longAmount)) {
            revert WrappedLongTransferFailed();
        }
        if (!wrappedCTData.wrappedInvalid.transferFrom(msg.sender, address(this), invalidAmount)) {
            revert WrappedInvalidTransferFailed();
        }

        // Contracts transfers Short/Long/Invalid ERC20 to wrapped1155Factory and gets
        // back Short/Long/Invalid ERC1155.
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.shortPositionId, shortAmount, address(this), wrappedCTData.shortData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.longPositionId, longAmount, address(this), wrappedCTData.longData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.invalidPositionId, invalidAmount, address(this), wrappedCTData.invalidData
        );

        // Track contract's decision outcome ERC1155 balance, in case it's > 0.
        uint256 decisionPositionId =
            conditionalTokens.getPositionId(ctParams.collateralToken, ctParams.parentCollectionId);
        uint256 initialBalance = conditionalTokens.balanceOf(address(this), decisionPositionId);

        // Redeem positions. Short/Long/Invalid/Invalid ERC1155 are burnt. Decision outcome
        // ERC1155 are minted in proportion of payouts.
        conditionalTokens.redeemPositions(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, _discreetPartition()
        );

        // Track contract's new decision outcome balance.
        uint256 finalBalance = conditionalTokens.balanceOf(address(this), decisionPositionId);
        uint256 redeemedAmount = finalBalance - initialBalance;

        // Contract transfers decision outcome ERC1155 redeemed amount to user.
        conditionalTokens.safeTransferFrom(address(this), msg.sender, decisionPositionId, redeemedAmount, "");
    }

    /// @dev Returns the discreet partition array [1,2,4] for the short/long/invalid outcomes.
    function _discreetPartition() private pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](3);
        partition[0] = 1;
        partition[1] = 2;
        partition[2] = 4;
        return partition;
    }
}
