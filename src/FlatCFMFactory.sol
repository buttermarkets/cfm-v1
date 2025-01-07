// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import "./libs/String31.sol";
import "./FlatCFMOracleAdapter.sol";
import "./FlatCFM.sol";
import "./ConditionalScalarMarket.sol";
import {
    FlatCFMQuestionParams,
    GenericScalarQuestionParams,
    ScalarParams,
    WrappedConditionalTokensData,
    ConditionalScalarCTParams
} from "./Types.sol";

contract FlatCFMFactory {
    using Clones for address;
    using String31 for string;

    uint256 public constant MAX_OUTCOMES = 50;
    // So that the outcome can fit in String31.
    uint256 public constant MAX_OUTCOME_NAME_LENGTH = 25;

    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    address public immutable conditionalScalarMarketImplementation;

    error InvalidOutcomeCount(uint256 outcomeCount);
    error InvalidOutcomeNameLength(string outcomeName);

    event FlatCFMCreated(address indexed market);

    event ConditionalMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    constructor(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;

        // This contract is never used directly; only cloned via EIP-1167.
        ConditionalScalarMarket master = new ConditionalScalarMarket();
        conditionalScalarMarketImplementation = address(master);
    }

    /// @notice Creates a FlatCFM and corresponding nested conditional markets.
    function create(
        uint256 decisionTemplateId,
        uint256 metricTemplateId,
        FlatCFMQuestionParams calldata flatCFMQParams,
        GenericScalarQuestionParams calldata genericScalarQParams,
        IERC20 collateralToken
    ) external returns (FlatCFM) {
        uint256 outcomeCount = flatCFMQParams.outcomeNames.length;
        if (outcomeCount == 0 || outcomeCount > MAX_OUTCOMES) {
            revert InvalidOutcomeCount(outcomeCount);
        }

        (FlatCFM cfm, bytes32 cfmConditionId) = createDecisionMarket(decisionTemplateId, flatCFMQParams, outcomeCount);

        emit FlatCFMCreated(address(cfm));

        for (uint256 i = 0; i < outcomeCount;) {
            ConditionalScalarMarket csm = createConditionalMarket(
                metricTemplateId, flatCFMQParams, i, genericScalarQParams, collateralToken, cfmConditionId
            );

            emit ConditionalMarketCreated(address(cfm), address(csm), i);

            unchecked {
                ++i;
            }
        }

        return cfm;
    }

    /// @dev 1) Asks a decision question on the oracle,
    ///      2) Prepares the condition in ConditionalTokens,
    ///      3) Deploys the FlatCFM contract.
    function createDecisionMarket(
        uint256 decisionTemplateId,
        FlatCFMQuestionParams calldata flatCFMQParams,
        uint256 outcomeCount
    ) private returns (FlatCFM, bytes32) {
        bytes32 cfmQuestionId = oracleAdapter.askDecisionQuestion(decisionTemplateId, flatCFMQParams);

        // +1 counts for Invalid.
        bytes32 cfmConditionId =
            conditionalTokens.getConditionId(address(oracleAdapter), cfmQuestionId, outcomeCount + 1);
        if (conditionalTokens.getOutcomeSlotCount(cfmConditionId) == 0) {
            conditionalTokens.prepareCondition(address(oracleAdapter), cfmQuestionId, outcomeCount + 1);
        }

        FlatCFM cfm = new FlatCFM(oracleAdapter, conditionalTokens, outcomeCount, cfmQuestionId, cfmConditionId);

        return (cfm, cfmConditionId);
    }

    ///@dev For each outcome,
    ///     1) Ask a metric question,
    ///     2) Prepare the child condition,
    ///     3) Deploy short/long ERC20 tokens,
    ///     4) Deploy the ConditionalScalarMarket contract.
    function createConditionalMarket(
        uint256 metricTemplateId,
        FlatCFMQuestionParams calldata flatCFMQParams,
        uint256 outcomeIndex,
        GenericScalarQuestionParams calldata genericScalarQParams,
        IERC20 collateralToken,
        bytes32 cfmConditionId
    ) private returns (ConditionalScalarMarket) {
        WrappedConditionalTokensData memory wrappedCTData;
        ConditionalScalarCTParams memory conditionalScalarCTParams;
        {
            string calldata outcomeName = flatCFMQParams.outcomeNames[outcomeIndex];
            if (bytes(outcomeName).length > MAX_OUTCOME_NAME_LENGTH) revert InvalidOutcomeNameLength(outcomeName);

            bytes32 csmQuestionId = oracleAdapter.askMetricQuestion(metricTemplateId, genericScalarQParams, outcomeName);

            // 3: Short, Long, Invalid.
            bytes32 csmConditionId = conditionalTokens.getConditionId(address(oracleAdapter), csmQuestionId, 3);
            if (conditionalTokens.getOutcomeSlotCount(csmConditionId) == 0) {
                conditionalTokens.prepareCondition(address(oracleAdapter), csmQuestionId, 3);
            }

            bytes32 decisionCollectionId = conditionalTokens.getCollectionId(0, cfmConditionId, 1 << outcomeIndex);
            wrappedCTData =
                deployWrappedConditiontalTokens(outcomeName, collateralToken, decisionCollectionId, csmConditionId);

            conditionalScalarCTParams = ConditionalScalarCTParams({
                questionId: csmQuestionId,
                conditionId: csmConditionId,
                parentCollectionId: decisionCollectionId,
                collateralToken: collateralToken
            });
        }

        ConditionalScalarMarket csm = ConditionalScalarMarket(conditionalScalarMarketImplementation.clone());
        csm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            conditionalScalarCTParams,
            ScalarParams({
                minValue: genericScalarQParams.scalarParams.minValue,
                maxValue: genericScalarQParams.scalarParams.maxValue
            }),
            wrappedCTData
        );

        return csm;
    }

    /// @dev Deploy short/long ERC20s for the nested condition.
    function deployWrappedConditiontalTokens(
        string calldata outcomeName,
        IERC20 collateralToken,
        bytes32 decisionCollectionId,
        bytes32 csmConditionId
    ) private returns (WrappedConditionalTokensData memory) {
        bytes memory shortData = abi.encodePacked(
            string.concat(outcomeName, "-Short").toString31(), string.concat(outcomeName, "-ST").toString31(), uint8(18)
        );
        bytes memory longData = abi.encodePacked(
            string.concat(outcomeName, "-Long").toString31(), string.concat(outcomeName, "-LG").toString31(), uint8(18)
        );
        bytes memory invalidData = abi.encodePacked(
            string.concat(outcomeName, "-Inv").toString31(), string.concat(outcomeName, "-XX").toString31(), uint8(18)
        );

        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, csmConditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, csmConditionId, 2)
        );
        uint256 invalidPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, csmConditionId, 4)
        );

        IERC20 wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPosId, shortData);
        IERC20 wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPosId, longData);
        IERC20 wrappedInvalid = wrapped1155Factory.requireWrapped1155(conditionalTokens, invalidPosId, invalidData);

        return WrappedConditionalTokensData({
            shortData: shortData,
            longData: longData,
            invalidData: invalidData,
            shortPositionId: shortPosId,
            longPositionId: longPosId,
            invalidPositionId: invalidPosId,
            wrappedShort: wrappedShort,
            wrappedLong: wrappedLong,
            wrappedInvalid: wrappedInvalid
        });
    }
}
