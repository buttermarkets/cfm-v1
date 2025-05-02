// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "../interfaces/IWrapped1155Factory.sol";
import "../interfaces/IConditionalTokens.sol";
import "../libs/String31.sol";
import "../FlatCFMOracleAdapter.sol";
import "../FlatCFM.sol";
import {
    FlatCFMQuestionParams, GenericScalarQuestionParams, ScalarParams, ConditionalScalarCTParams
} from "../Types.sol";
import {InvalidlessWrappedConditionalTokensData} from "./Types.sol";
import "./InvalidlessConditionalScalarMarket.sol";

/// @title FlatCFMFactory
/// @notice Factory contract to create "flat" Conditional Funding Markets (CFMs)
///         and conditional scalar markets for each outcome.
contract InvalidlessFlatCFMFactory {
    using Clones for address;
    using String31 for string;

    /// @dev Container struct for storing Conditional Scalar Market deployment
    /// parameters temporarily.
    struct DeploymentParams {
        IERC20 collateralToken;
        uint256 metricTemplateId;
        GenericScalarQuestionParams genericScalarQuestionParams;
        uint256[2] defaultInvalidPayouts;
        bytes32 decisionConditionId;
        string[] outcomeNames;
    }

    /// @notice Maximum outcome count for decision markets (+1 for 'Invalid').
    uint256 public constant MAX_OUTCOME_COUNT = 255;

    /// @notice Maximum length for each outcome name to fit in a String31 slot.
    uint256 public constant MAX_OUTCOME_NAME_LENGTH = 25;

    /// @notice Gnosis Conditional Tokens contract.
    IConditionalTokens public immutable conditionalTokens;

    /// @notice Factory for wrapping conditional tokens into ERC20.
    IWrapped1155Factory public immutable wrapped1155Factory;

    /// @notice Implementation for cloned FlatCFM logic.
    address public immutable flatCfmImplementation;

    /// @notice Implementation for cloned InvalidlessConditionalScalarMarket logic.
    address public immutable invalidlessConditionalScalarMarketImplementation;

    /// @dev Tracks which outcome index is to be deployed next for each FlatCFM.
    mapping(FlatCFM => uint256) public nextOutcomeToDeploy;

    /// @dev Stores deployment parameters for each FlatCFM until
    ///      all its conditional scalar markets are created.
    mapping(FlatCFM => DeploymentParams) public paramsToDeploy;

    error InvalidOutcomeCount();
    error InvalidOutcomeNameLength(string outcomeName);
    error NoConditionalScalarMarketToDeploy();
    error InvalidPayoutsCannotBeBothZero();
    error InvalidPayoutsSumOverflow();

    /// @notice Emitted when a new FlatCFM is created.
    /// @param market Address of the new FlatCFM contract.
    /// @param conditionId Conditional Tokens' condition ID.
    event FlatCFMCreated(address indexed market, bytes32 conditionId, address deployer);

    /// @notice Emitted when a new InvalidlessConditionalScalarMarket is created for a specific
    ///         outcome of a FlatCFM.
    /// @param decisionMarket The associated FlatCFM.
    /// @param conditionalMarket The newly deployed InvalidlessConditionalScalarMarket.
    /// @param outcomeIndex Which outcome index this market corresponds to.
    event InvalidlessConditionalScalarMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    /// @param _conditionalTokens Gnosis Conditional Tokens contract.
    /// @param _wrapped1155Factory Factory for ERC20-wrapped positions.
    constructor(IConditionalTokens _conditionalTokens, IWrapped1155Factory _wrapped1155Factory) {
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
        flatCfmImplementation = address(new FlatCFM());
        invalidlessConditionalScalarMarketImplementation = address(new InvalidlessConditionalScalarMarket());
    }

    /// @notice Creates a new FlatCFM (decision market).
    /// @dev 1) Asks a "decision question" via the oracle adapter.
    ///      2) Prepares condition in ConditionalTokens if not already prepared.
    ///      3) Stores parameters for subsequent scalar market deployments.
    ///      4) Deploys a FlatCFM clone.
    /// @param oracleAdapter Oracle adapter to call for question creation.
    /// @param decisionTemplateId Template ID used by the oracle for a decision question.
    /// @param metricTemplateId Template ID used by the oracle for metric (scalar) questions.
    /// @param flatCFMQParams Struct with outcome names and question opening time.
    /// @param genericScalarQuestionParams Struct with scalar range info and opening time.
    /// @param defaultInvalidPayouts Default payouts to use if the answer is invalid [short, long].
    /// @param collateralToken ERC20 token used as the collateral (e.g., DAI).
    /// @param metadataUri Metadata URI for front-ends.
    /// @return cfm Deployed FlatCFM clone address.
    function createFlatCFM(
        FlatCFMOracleAdapter oracleAdapter,
        uint256 decisionTemplateId,
        uint256 metricTemplateId,
        FlatCFMQuestionParams calldata flatCFMQParams,
        GenericScalarQuestionParams calldata genericScalarQuestionParams,
        uint256[2] calldata defaultInvalidPayouts,
        IERC20 collateralToken,
        string calldata metadataUri
    ) external payable returns (FlatCFM cfm) {
        // Add validation for defaultInvalidPayouts
        if (defaultInvalidPayouts[0] == 0 && defaultInvalidPayouts[1] == 0) {
            revert InvalidPayoutsCannotBeBothZero();
        }

        // Check for overflow in defaultInvalidPayouts sum
        // Note: In Solidity 0.8+, this addition will revert on overflow by default
        // We perform it here explicitly to guarantee reportPayouts won't fail later
        uint256 sumPayouts = defaultInvalidPayouts[0] + defaultInvalidPayouts[1];

        uint256 outcomeCount = flatCFMQParams.outcomeNames.length;
        if (outcomeCount == 0 || outcomeCount > MAX_OUTCOME_COUNT) {
            revert InvalidOutcomeCount();
        }
        for (uint256 i = 0; i < outcomeCount; i++) {
            string memory outcomeName = flatCFMQParams.outcomeNames[i];
            if (bytes(outcomeName).length > MAX_OUTCOME_NAME_LENGTH) revert InvalidOutcomeNameLength(outcomeName);
        }

        cfm = FlatCFM(flatCfmImplementation.clone());

        bytes32 decisionQuestionId =
            oracleAdapter.askDecisionQuestion{value: msg.value}(decisionTemplateId, flatCFMQParams);

        // +1 for 'Invalid' slot.
        bytes32 decisionConditionId =
            conditionalTokens.getConditionId(address(cfm), decisionQuestionId, outcomeCount + 1);
        if (conditionalTokens.getOutcomeSlotCount(decisionConditionId) == 0) {
            conditionalTokens.prepareCondition(address(cfm), decisionQuestionId, outcomeCount + 1);
        }

        paramsToDeploy[cfm] = DeploymentParams({
            collateralToken: collateralToken,
            metricTemplateId: metricTemplateId,
            genericScalarQuestionParams: genericScalarQuestionParams,
            defaultInvalidPayouts: defaultInvalidPayouts,
            decisionConditionId: decisionConditionId,
            outcomeNames: flatCFMQParams.outcomeNames
        });

        cfm.initialize(oracleAdapter, conditionalTokens, outcomeCount, decisionQuestionId, metadataUri);

        emit FlatCFMCreated(address(cfm), decisionConditionId, msg.sender);
    }

    /// @notice Creates an InvalidlessConditionalScalarMarket for the next outcome in the given FlatCFM.
    /// @dev Similar to createConditionalScalarMarket but creates a market without an invalid outcome.
    /// @param cfm The FlatCFM for which to deploy the next scalar market.
    /// @return icsm The newly deployed InvalidlessConditionalScalarMarket.
    function createConditionalScalarMarket(FlatCFM cfm)
        external
        payable
        returns (InvalidlessConditionalScalarMarket icsm)
    {
        if (paramsToDeploy[cfm].outcomeNames.length == 0) revert NoConditionalScalarMarketToDeploy();

        uint256 outcomeIndex = nextOutcomeToDeploy[cfm];
        FlatCFMOracleAdapter oracleAdapter = cfm.oracleAdapter();
        DeploymentParams memory params = paramsToDeploy[cfm];

        icsm = InvalidlessConditionalScalarMarket(invalidlessConditionalScalarMarketImplementation.clone());

        InvalidlessWrappedConditionalTokensData memory wrappedCTData;
        ConditionalScalarCTParams memory conditionalScalarCTParams;

        if (outcomeIndex == cfm.outcomeCount() - 1) {
            // Once the final outcome is deployed, clean up storage for this FlatCFM.
            delete nextOutcomeToDeploy[cfm];
            delete paramsToDeploy[cfm];
        } else {
            nextOutcomeToDeploy[cfm]++;
        }

        {
            string memory outcomeName = params.outcomeNames[outcomeIndex];
            bytes32 csmQuestionId = oracleAdapter.askMetricQuestion{value: msg.value}(
                params.metricTemplateId, params.genericScalarQuestionParams, outcomeName
            );

            // 2 outcomes: Short, Long (no Invalid)
            bytes32 csmConditionId = conditionalTokens.getConditionId(address(icsm), csmQuestionId, 2);
            if (conditionalTokens.getOutcomeSlotCount(csmConditionId) == 0) {
                conditionalTokens.prepareCondition(address(icsm), csmQuestionId, 2);
            }

            bytes32 decisionCollectionId =
                conditionalTokens.getCollectionId(0, params.decisionConditionId, 1 << outcomeIndex);

            wrappedCTData = _deployWrappedConditionalTokens(
                outcomeName, params.collateralToken, decisionCollectionId, csmConditionId
            );

            conditionalScalarCTParams = ConditionalScalarCTParams({
                questionId: csmQuestionId,
                conditionId: csmConditionId,
                parentCollectionId: decisionCollectionId,
                collateralToken: params.collateralToken
            });
        }

        icsm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            conditionalScalarCTParams,
            ScalarParams({
                minValue: params.genericScalarQuestionParams.scalarParams.minValue,
                maxValue: params.genericScalarQuestionParams.scalarParams.maxValue
            }),
            wrappedCTData,
            params.defaultInvalidPayouts
        );

        emit InvalidlessConditionalScalarMarketCreated(address(cfm), address(icsm), outcomeIndex);
    }

    /// @dev Internal helper to deploy two wrapped ERC1155 tokens (Short, Long)
    ///      for the nested condition, returning their data.
    function _deployWrappedConditionalTokens(
        string memory outcomeName,
        IERC20 collateralToken,
        bytes32 decisionCollectionId,
        bytes32 csmConditionId
    ) private returns (InvalidlessWrappedConditionalTokensData memory) {
        bytes memory shortData = abi.encodePacked(
            string.concat(outcomeName, "-Short").toString31(), string.concat(outcomeName, "-ST").toString31(), uint8(18)
        );
        bytes memory longData = abi.encodePacked(
            string.concat(outcomeName, "-Long").toString31(), string.concat(outcomeName, "-LG").toString31(), uint8(18)
        );

        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, csmConditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, csmConditionId, 2)
        );

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
