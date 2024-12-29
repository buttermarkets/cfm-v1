// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import {ScalarParams, ConditionalScalarCTParams, WrappedConditionalTokensData} from "./Types.sol";
import "./FlatCFMOracleAdapter.sol";

contract ConditionalScalarMarket is ERC1155Holder {
    // Decision market attributes:
    FlatCFMOracleAdapter public oracleAdapter;
    IConditionalTokens public conditionalTokens;
    IWrapped1155Factory public wrapped1155Factory;
    // ConditionalTokens-specific attributes:
    ConditionalScalarCTParams public ctParams;
    // Scalar market-specific attributes:
    ScalarParams public scalarParams;
    // Wrapped conditional tokens data:
    WrappedConditionalTokensData public wrappedCTData;

    // State attributes:
    bool public initialized;

    /// @notice Initialize function called by each clone.
    function initialize(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory,
        ConditionalScalarCTParams memory _conditionalScalarCTParams,
        ScalarParams memory _scalarParams,
        WrappedConditionalTokensData memory _wrappedCTData
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;

        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
        ctParams = _conditionalScalarCTParams;
        scalarParams = _scalarParams;
        wrappedCTData = _wrappedCTData;
    }

    /// @notice Reports payouts corresponding to the scalar value reported by
    /// the oracle. If the oracle value is invalid, report 50/50.
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(ctParams.questionId);
        uint256[] memory payouts = new uint256[](2);

        // If the answer is invalid, no payouts are returned.
        // TODO: test all cases, including invalid. In invalid, the user should
        // still be able to merge positions.
        if (!oracleAdapter.isInvalid(answer)) {
            uint256 numericAnswer = uint256(answer);
            if (numericAnswer <= scalarParams.minValue) {
                payouts[0] = 1;
            } else if (numericAnswer >= scalarParams.maxValue) {
                payouts[1] = 1;
            } else {
                payouts[0] = scalarParams.maxValue - numericAnswer;
                payouts[1] = numericAnswer - scalarParams.minValue;
            }
        } else {
            payouts[0] = 1;
            payouts[1] = 1;
        }

        // `reportPayouts` requires that the condition is already prepared and
        // payouts aren't reported yet.
        conditionalTokens.reportPayouts(ctParams.questionId, payouts);
    }

    // XXX Split/m/r in a different way if the parent is resolved? Probably not
    // FIXME Test split/m/r in all different state cases: DecisionResolved? x
    // ConditionalResolved?
    /// @notice Splits decision outcome into wrapped Long/Short.
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
        // Long/Short ERC1155 are minted to the contract.
        conditionalTokens.splitPosition(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, discreetPartition(), amount
        );

        // Contract transfers Long/Short ERC1155 to wrapped1155Factory and
        // gets back Long/Short ERC20.
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), wrappedCTData.shortPositionId, amount, wrappedCTData.shortData
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), wrappedCTData.longPositionId, amount, wrappedCTData.longData
        );

        // Contract transfers Long/Short ERC20 to user.
        require(wrappedCTData.wrappedShort.transfer(msg.sender, amount), "split short erc20 transfer failed");
        require(wrappedCTData.wrappedLong.transfer(msg.sender, amount), "split long erc20 transfer failed");
    }

    /// @notice Merges wrapped Long/Short back into decision outcome.
    function merge(uint256 amount) external {
        require(amount > 0, "amount must be positive");

        // User transfers Long/Short ERC20 to contract.
        require(
            wrappedCTData.wrappedShort.transferFrom(msg.sender, address(this), amount), "short token transfer failed"
        );
        require(wrappedCTData.wrappedLong.transferFrom(msg.sender, address(this), amount), "long token transfer failed");

        // Contract transfers Long/Short ERC20 to wrapped1155Factory and gets
        // back Long/Short ERC1155.
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.shortPositionId, amount, address(this), wrappedCTData.shortData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.longPositionId, amount, address(this), wrappedCTData.longData
        );

        // Merge position. Long/Short ERC1155 are burnt. Decision outcome
        // ERC1155 are minted.
        conditionalTokens.mergePositions(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, discreetPartition(), amount
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

    /// @notice Redeems Long/Short positions after condition resolution.
    /// @param shortAmount Amount of Short tokens to redeem (can be 0).
    /// @param longAmount Amount of Long tokens to redeem (can be 0).
    function redeem(uint256 shortAmount, uint256 longAmount) external {
        uint256 den = conditionalTokens.payoutDenominator(ctParams.conditionId);
        require(den > 0, "condition not resolved");

        // User transfers Long/Short ERC20 to contract.
        require(
            wrappedCTData.wrappedShort.transferFrom(msg.sender, address(this), shortAmount),
            "short token transfer failed"
        );
        require(
            wrappedCTData.wrappedLong.transferFrom(msg.sender, address(this), longAmount), "long token transfer failed"
        );

        // Contracts transfers Long/Short ERC20 to wrapped1155Factory and gets
        // back Long/Short ERC1155.
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.shortPositionId, shortAmount, address(this), wrappedCTData.shortData
        );
        wrapped1155Factory.unwrap(
            conditionalTokens, wrappedCTData.longPositionId, longAmount, address(this), wrappedCTData.longData
        );

        uint256 decisionPositionId =
            conditionalTokens.getPositionId(ctParams.collateralToken, ctParams.parentCollectionId);
        uint256 initialBalance = conditionalTokens.balanceOf(address(this), decisionPositionId);

        // Redeem positions. Long/Short ERC1155 are burnt. Decision outcome
        // ERC1155 are minted in proportion of payouts.
        conditionalTokens.redeemPositions(
            ctParams.collateralToken, ctParams.parentCollectionId, ctParams.conditionId, discreetPartition()
        );

        uint256 finalBalance = conditionalTokens.balanceOf(address(this), decisionPositionId);
        uint256 redeemedAmount = finalBalance - initialBalance;

        // Contract transfers ERC20 decision outcome tokens to user.
        conditionalTokens.safeTransferFrom(address(this), msg.sender, decisionPositionId, redeemedAmount, "");
    }

    function discreetPartition() private pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        return partition;
    }
}
