// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../interfaces/IWrapped1155Factory.sol";
import "../interfaces/IConditionalTokens.sol";
import "../libs/String31.sol";
import "../FlatCFMOracleAdapter.sol";
import {ScalarParams, ConditionalScalarCTParams, GenericScalarQuestionParams} from "../Types.sol";
import {InvalidlessWrappedConditionalTokensData} from "./Types.sol";
import "./InvalidlessConditionalScalarMarket.sol";

/// @title InvalidlessConditionalScalarMarketFactory
/// @notice Factory contract to create standalone InvalidlessConditionalScalarMarkets
contract InvalidlessConditionalScalarMarketFactory {
    using Clones for address;
    using String31 for string;

    /// @notice Gnosis Conditional Tokens contract.
    IConditionalTokens public immutable conditionalTokens;

    /// @notice Factory for wrapping conditional tokens into ERC20.
    IWrapped1155Factory public immutable wrapped1155Factory;

    /// @notice Implementation for cloned InvalidlessConditionalScalarMarket logic.
    address public immutable invalidlessConditionalScalarMarketImplementation;

    /// @notice Maximum length for each outcome name to fit in a String31 slot.
    uint256 public constant MAX_OUTCOME_NAME_LENGTH = 25;

    error InvalidPayoutsCannotBeBothZero();
    error InvalidScalarRange();
    error InvalidOutcomeNameLength(string outcomeName);

    /// @notice Emitted when a new InvalidlessConditionalScalarMarket is created.
    /// @param decisionMarket The associated FlatCFM (0 for standalone markets).
    /// @param conditionalMarket The newly deployed InvalidlessConditionalScalarMarket.
    /// @param outcomeIndex Which outcome index this market corresponds to (0 for standalone).
    event InvalidlessConditionalScalarMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    /// @param _conditionalTokens Gnosis Conditional Tokens contract.
    /// @param _wrapped1155Factory Factory for ERC20-wrapped positions.
    constructor(IConditionalTokens _conditionalTokens, IWrapped1155Factory _wrapped1155Factory) {
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
        invalidlessConditionalScalarMarketImplementation = address(new InvalidlessConditionalScalarMarket());
    }

    /// @notice Creates a standalone InvalidlessConditionalScalarMarket.
    /// @param oracleAdapter Oracle adapter to call for question creation.
    /// @param templateId Template ID used by the oracle for the scalar question.
    /// @param outcomeName Name of the outcome for this scalar market.
    /// @param genericScalarQuestionParams Struct containing scalar range info and opening time.
    /// @param defaultInvalidPayouts Default payouts to use if the answer is invalid [short, long].
    /// @param collateralToken ERC20 token used as the collateral.
    /// @return icsm Deployed InvalidlessConditionalScalarMarket clone address.
    function createInvalidlessConditionalScalarMarket(
        FlatCFMOracleAdapter oracleAdapter,
        uint256 templateId,
        string calldata outcomeName,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        uint256[2] calldata defaultInvalidPayouts,
        IERC20 collateralToken
    ) external payable returns (InvalidlessConditionalScalarMarket icsm) {
        // Validate inputs
        if (bytes(outcomeName).length > MAX_OUTCOME_NAME_LENGTH) {
            revert InvalidOutcomeNameLength(outcomeName);
        }
        if (defaultInvalidPayouts[0] == 0 && defaultInvalidPayouts[1] == 0) {
            revert InvalidPayoutsCannotBeBothZero();
        }
        if (genericScalarQuestionParams.scalarParams.maxValue <= genericScalarQuestionParams.scalarParams.minValue) {
            revert InvalidScalarRange();
        }

        // Check for overflow in defaultInvalidPayouts sum
        // Note: In Solidity 0.8+, this addition will revert on overflow by default
        require(defaultInvalidPayouts[0] + defaultInvalidPayouts[1] >= 0);

        // Deploy the market clone
        icsm = InvalidlessConditionalScalarMarket(invalidlessConditionalScalarMarketImplementation.clone());

        // Ask the metric question
        bytes32 questionId =
            oracleAdapter.askMetricQuestion{value: msg.value}(templateId, genericScalarQuestionParams, outcomeName);

        // Prepare condition (2 outcomes: Short, Long)
        bytes32 conditionId = conditionalTokens.getConditionId(address(icsm), questionId, 2);
        if (conditionalTokens.getOutcomeSlotCount(conditionId) == 0) {
            conditionalTokens.prepareCondition(address(icsm), questionId, 2);
        }

        // Deploy wrapped conditional tokens
        InvalidlessWrappedConditionalTokensData memory wrappedCTData =
            _deployWrappedConditionalTokens(outcomeName, collateralToken, conditionId);

        // Initialize the market
        ConditionalScalarCTParams memory ctParams = ConditionalScalarCTParams({
            questionId: questionId,
            conditionId: conditionId,
            parentCollectionId: bytes32(0), // No parent collection for standalone market
            collateralToken: collateralToken
        });

        icsm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            ctParams,
            genericScalarQuestionParams.scalarParams,
            wrappedCTData,
            defaultInvalidPayouts
        );

        emit InvalidlessConditionalScalarMarketCreated(address(0), address(icsm), 0);
    }

    /// @dev Internal helper to deploy two wrapped ERC1155 tokens (Short, Long)
    ///      for the condition, returning their data.
    function _deployWrappedConditionalTokens(string memory outcomeName, IERC20 collateralToken, bytes32 conditionId)
        private
        returns (InvalidlessWrappedConditionalTokensData memory)
    {
        uint8 decimals = IERC20Metadata(address(collateralToken)).decimals();

        // Create token names and symbols
        bytes memory shortData = abi.encodePacked(
            string.concat(outcomeName, "-Short").toString31(), string.concat(outcomeName, "-ST").toString31(), decimals
        );
        bytes memory longData = abi.encodePacked(
            string.concat(outcomeName, "-Long").toString31(), string.concat(outcomeName, "-LG").toString31(), decimals
        );

        // Get position IDs (no parent collection for standalone market)
        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, 2)
        );

        // Deploy wrapped tokens
        IERC20 wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPosId, shortData);
        IERC20 wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPosId, longData);

        return InvalidlessWrappedConditionalTokensData({
            shortData: shortData,
            longData: longData,
            shortPositionId: shortPosId,
            longPositionId: longPosId,
            wrappedShort: wrappedShort,
            wrappedLong: wrappedLong
        });
    }
}
