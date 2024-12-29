// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
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

    uint256 constant MAX_OUTCOMES = 50;

    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    address public immutable conditionalScalarMarketImplementation;

    error InvalidOutcomeCount(uint256 outcomeCount, uint256 maxOutcomeCount);
    error InvalidOutcomeNameLength(string outcomeName, uint256 maxLength);
    error InvalidString31Length(string _string);

    event FlatCFMCreated(
        address indexed market,
        string roundName,
        string metricName,
        string startDate,
        string endDate,
        address collateralToken
    );

    event ConditionalMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex, string outcomeName
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
        FlatCFMQuestionParams calldata flatCFMQParams,
        GenericScalarQuestionParams calldata genericScalarQParams,
        IERC20 collateralToken
    ) external returns (FlatCFM) {
        uint256 outcomeCount = flatCFMQParams.outcomeNames.length;
        if (outcomeCount == 0 || outcomeCount > MAX_OUTCOMES) {
            revert InvalidOutcomeCount(outcomeCount, MAX_OUTCOMES);
        }

        (FlatCFM cfm, bytes32 cfmConditionId) = createDecisionMarket(flatCFMQParams, outcomeCount);

        emit FlatCFMCreated(
            address(cfm),
            flatCFMQParams.roundName,
            genericScalarQParams.metricName,
            genericScalarQParams.startDate,
            genericScalarQParams.endDate,
            address(collateralToken)
        );

        for (uint256 i = 0; i < outcomeCount;) {
            ConditionalScalarMarket csm =
                createConditionalMarket(flatCFMQParams, i, genericScalarQParams, collateralToken, cfmConditionId);

            emit ConditionalMarketCreated(address(cfm), address(csm), i, flatCFMQParams.outcomeNames[i]);

            unchecked {
                ++i;
            }
        }

        return cfm;
    }

    /// @dev 1) Asks a decision question on the oracle,
    ///      2) Prepares the condition in ConditionalTokens,
    ///      3) Deploys the FlatCFM contract.
    function createDecisionMarket(FlatCFMQuestionParams calldata flatCFMQParams, uint256 outcomeCount)
        private
        returns (FlatCFM, bytes32)
    {
        bytes32 cfmQuestionId = oracleAdapter.askDecisionQuestion(flatCFMQParams);

        conditionalTokens.prepareCondition(address(oracleAdapter), cfmQuestionId, outcomeCount);
        bytes32 cfmConditionId = conditionalTokens.getConditionId(address(oracleAdapter), cfmQuestionId, outcomeCount);

        FlatCFM cfm = new FlatCFM(oracleAdapter, conditionalTokens, outcomeCount, cfmQuestionId, cfmConditionId);

        return (cfm, cfmConditionId);
    }

    ///@dev For each outcome,
    ///     1) Ask a metric question,
    ///     2) Prepare the child condition,
    ///     3) Deploy short/long ERC20 tokens,
    ///     4) Deploy the ConditionalScalarMarket contract.
    function createConditionalMarket(
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
            if (bytes(outcomeName).length > 25) revert InvalidOutcomeNameLength(outcomeName, 25);

            bytes32 metricQ = oracleAdapter.askMetricQuestion(genericScalarQParams, outcomeName);

            conditionalTokens.prepareCondition(address(this), metricQ, 2);
            bytes32 conditionalConditionId = conditionalTokens.getConditionId(address(this), metricQ, 2);

            bytes32 decisionCollectionId = conditionalTokens.getCollectionId(0, cfmConditionId, 1 << outcomeIndex);
            wrappedCTData = deployWrappedConditiontalTokens(
                outcomeName, collateralToken, decisionCollectionId, conditionalConditionId
            );

            conditionalScalarCTParams = ConditionalScalarCTParams({
                questionId: metricQ,
                conditionId: conditionalConditionId,
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
        bytes32 conditionalConditionId
    ) private returns (WrappedConditionalTokensData memory) {
        bytes memory shortData = abi.encodePacked(
            toString31(string.concat(outcomeName, "-Short")), toString31(string.concat(outcomeName, "-ST")), uint8(18)
        );
        bytes memory longData = abi.encodePacked(
            toString31(string.concat(outcomeName, "-Long")), toString31(string.concat(outcomeName, "-LG")), uint8(18)
        );

        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, conditionalConditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, conditionalConditionId, 2)
        );

        IERC20 wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPosId, shortData);
        IERC20 wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPosId, longData);

        return WrappedConditionalTokensData({
            shortData: shortData,
            longData: longData,
            shortPositionId: shortPosId,
            longPositionId: longPosId,
            wrappedShort: wrappedShort,
            wrappedLong: wrappedLong
        });
    }

    // TODO test this.
    // From https://github.com/gnosis/1155-to-20/pull/4#discussion_r573630922
    /// @dev Encodes a short string (less than than 31 bytes long) as for storage as expected by Solidity.
    /// <https://docs.soliditylang.org/en/v0.8.1/internals/layout_in_storage.html#bytes-and-string>
    function toString31(string memory value) private pure returns (bytes32 encodedString) {
        uint256 length = bytes(value).length;
        if (length > 31) revert InvalidString31Length(value);

        // Read the right-padded string data, which is guaranteed to fit into a single
        // word because its length is less than 32.
        assembly {
            encodedString := mload(add(value, 0x20))
        }

        // Now mask the string data, this ensures that the bytes past the string length
        // are all 0s.
        bytes32 mask = bytes32(type(uint256).max << ((32 - length) << 3));
        encodedString = encodedString & mask;

        // Finally, set the least significant byte to be the hex length of the encoded
        // string, that is its byte-length times two.
        encodedString = encodedString | bytes32(length << 1);
    }
}
