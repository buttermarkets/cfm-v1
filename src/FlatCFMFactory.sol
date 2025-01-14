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

    struct DeploymentParams {
        IERC20 collateralToken;
        uint256 metricTemplateId;
        GenericScalarQuestionParams genericScalarQuestionParams;
        bytes32 decisionConditionId;
        string[] outcomeNames;
    }

    // In line with ConditionalTokens, +1 for Invalid.
    uint256 public constant MAX_OUTCOME_COUNT = 255;
    // So that the outcome can fit in String31.
    uint256 public constant MAX_OUTCOME_NAME_LENGTH = 25;

    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    address public immutable flatCfmImplementation;
    address public immutable conditionalScalarMarketImplementation;

    // How many outcomes there are left to deploy.
    mapping(FlatCFM => uint256) public nextOutcomeToDeploy;
    mapping(FlatCFM => DeploymentParams) public paramsToDeploy;

    error InvalidOutcomeCount();
    error InvalidOutcomeNameLength(string outcomeName);
    error NoConditionalScalarMarketToDeploy();

    event FlatCFMCreated(address indexed market, bytes32 conditionId);

    event ConditionalScalarMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    constructor(IConditionalTokens _conditionalTokens, IWrapped1155Factory _wrapped1155Factory) {
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;

        // These contracts are never used directly; only cloned via EIP-1167.
        flatCfmImplementation = address(new FlatCFM());
        conditionalScalarMarketImplementation = address(new ConditionalScalarMarket());
    }

    /// @notice Creates a FlatCFM. Corresponding conditional markets need to be
    ///     created by separate calls to `createConditionalScalarMarket`.
    /// @dev 1) Asks a decision question on the oracle,
    ///      2) Prepares the condition in ConditionalTokens,
    ///      3) Deploys the FlatCFM contract.
    // All parameters for children conditional markets need to be stored on
    // chain, in the FlatCFM instance, to make sure that only the original
    // deployer's intention is respected.
    function createFlatCFM(
        FlatCFMOracleAdapter oracleAdapter,
        uint256 decisionTemplateId,
        uint256 metricTemplateId,
        FlatCFMQuestionParams calldata flatCFMQParams,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        IERC20 collateralToken,
        string calldata metadataUri
    ) external returns (FlatCFM cfm) {
        uint256 outcomeCount = flatCFMQParams.outcomeNames.length;
        if (outcomeCount == 0 || outcomeCount > MAX_OUTCOME_COUNT) {
            revert InvalidOutcomeCount();
        }
        for (uint256 i = 0; i < outcomeCount; i++) {
            string memory outcomeName = flatCFMQParams.outcomeNames[i];
            if (bytes(outcomeName).length > MAX_OUTCOME_NAME_LENGTH) revert InvalidOutcomeNameLength(outcomeName);
        }

        cfm = FlatCFM(flatCfmImplementation.clone());
        nextOutcomeToDeploy[cfm] = 0;

        bytes32 decisionQuestionId = oracleAdapter.askDecisionQuestion(decisionTemplateId, flatCFMQParams);

        // +1 counts for Invalid.
        bytes32 decisionConditionId =
            conditionalTokens.getConditionId(address(cfm), decisionQuestionId, outcomeCount + 1);
        if (conditionalTokens.getOutcomeSlotCount(decisionConditionId) == 0) {
            conditionalTokens.prepareCondition(address(cfm), decisionQuestionId, outcomeCount + 1);
        }

        paramsToDeploy[cfm] = DeploymentParams({
            collateralToken: collateralToken,
            metricTemplateId: metricTemplateId,
            genericScalarQuestionParams: genericScalarQuestionParams,
            decisionConditionId: decisionConditionId,
            outcomeNames: flatCFMQParams.outcomeNames
        });

        cfm.initialize(oracleAdapter, conditionalTokens, outcomeCount, decisionQuestionId, metadataUri);

        emit FlatCFMCreated(address(cfm), decisionConditionId);
    }

    function createConditionalScalarMarket(FlatCFM cfm) external returns (ConditionalScalarMarket csm) {
        if (paramsToDeploy[cfm].outcomeNames.length == 0) revert NoConditionalScalarMarketToDeploy();

        uint256 outcomeIndex = nextOutcomeToDeploy[cfm];
        FlatCFMOracleAdapter oracleAdapter = cfm.oracleAdapter();
        DeploymentParams memory params = paramsToDeploy[cfm];
        csm = ConditionalScalarMarket(conditionalScalarMarketImplementation.clone());

        WrappedConditionalTokensData memory wrappedCTData;
        ConditionalScalarCTParams memory conditionalScalarCTParams;

        if (outcomeIndex == cfm.outcomeCount() - 1) {
            delete nextOutcomeToDeploy[cfm];
            delete paramsToDeploy[cfm];
        } else {
            nextOutcomeToDeploy[cfm]++;
        }

        {
            string memory outcomeName = params.outcomeNames[outcomeIndex];
            bytes32 csmQuestionId = oracleAdapter.askMetricQuestion(
                params.metricTemplateId, params.genericScalarQuestionParams, outcomeName
            );

            // 3: Short, Long, Invalid.
            bytes32 csmConditionId = conditionalTokens.getConditionId(address(csm), csmQuestionId, 3);
            if (conditionalTokens.getOutcomeSlotCount(csmConditionId) == 0) {
                conditionalTokens.prepareCondition(address(csm), csmQuestionId, 3);
            }

            bytes32 decisionCollectionId =
                conditionalTokens.getCollectionId(0, params.decisionConditionId, 1 << outcomeIndex);
            wrappedCTData = _deployWrappedConditiontalTokens(
                outcomeName, params.collateralToken, decisionCollectionId, csmConditionId
            );

            conditionalScalarCTParams = ConditionalScalarCTParams({
                questionId: csmQuestionId,
                conditionId: csmConditionId,
                parentCollectionId: decisionCollectionId,
                collateralToken: params.collateralToken
            });
        }

        csm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            conditionalScalarCTParams,
            ScalarParams({
                minValue: params.genericScalarQuestionParams.scalarParams.minValue,
                maxValue: params.genericScalarQuestionParams.scalarParams.maxValue
            }),
            wrappedCTData
        );

        emit ConditionalScalarMarketCreated(address(cfm), address(csm), outcomeIndex);
    }

    /// @dev Deploy short/long ERC20s for the nested condition.
    function _deployWrappedConditiontalTokens(
        string memory outcomeName,
        IERC20 collateralToken,
        bytes32 decisionCollectionId,
        bytes32 csmConditionId
    ) internal returns (WrappedConditionalTokensData memory) {
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
