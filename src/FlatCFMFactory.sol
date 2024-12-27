// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

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
    uint256 constant MAX_OUTCOMES = 50;

    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    event FlatCFMCreated(address indexed market, string roundName, address collateralToken);

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
    }

    /// @notice Creates a FlatCFM and corresponding nested conditional markets.
    function create(
        FlatCFMQuestionParams calldata flatCFMQParams,
        GenericScalarQuestionParams calldata genericScalarQParams,
        IERC20 collateralToken
    ) external returns (FlatCFM) {
        uint256 outcomeCount = flatCFMQParams.outcomeNames.length;
        // Early revert if outcomeCount is excessively large (for gas safety).
        require(outcomeCount > 0 && outcomeCount <= MAX_OUTCOMES, "Invalid outcome count");

        // Create the decision market.
        (FlatCFM cfm, bytes32 cfmConditionId) = createDecisionMarket(flatCFMQParams, outcomeCount, collateralToken);

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
    function createDecisionMarket(
        FlatCFMQuestionParams calldata flatCFMQParams,
        uint256 outcomeCount,
        IERC20 collateralToken
    ) private returns (FlatCFM, bytes32) {
        bytes32 cfmQuestionId = oracleAdapter.askDecisionQuestion(flatCFMQParams);

        conditionalTokens.prepareCondition(address(oracleAdapter), cfmQuestionId, outcomeCount);
        bytes32 cfmConditionId = conditionalTokens.getConditionId(address(oracleAdapter), cfmQuestionId, outcomeCount);

        FlatCFM cfm = new FlatCFM(oracleAdapter, conditionalTokens, outcomeCount, cfmQuestionId, cfmConditionId);

        emit FlatCFMCreated(address(cfm), flatCFMQParams.roundName, address(collateralToken));

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
        string calldata outcomeName = flatCFMQParams.outcomeNames[outcomeIndex];
        require(bytes(outcomeName).length <= 25, "Outcome name too long");

        bytes32 metricQ = oracleAdapter.askMetricQuestion(genericScalarQParams, outcomeName);

        conditionalTokens.prepareCondition(address(this), metricQ, 2);
        bytes32 conditionalConditionId = conditionalTokens.getConditionId(address(this), metricQ, 2);

        bytes32 decisionCollectionId = conditionalTokens.getCollectionId(0, cfmConditionId, 1 << outcomeIndex);
        WrappedConditionalTokensData memory wrappedCTData =
            deployWrappedConditiontalTokens(outcomeName, collateralToken, decisionCollectionId, conditionalConditionId);

        ConditionalScalarMarket csm = new ConditionalScalarMarket(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            ConditionalScalarCTParams({
                questionId: metricQ,
                conditionId: conditionalConditionId,
                parentCollectionId: decisionCollectionId,
                collateralToken: collateralToken
            }),
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

        // Compute positions
        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, conditionalConditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(decisionCollectionId, conditionalConditionId, 2)
        );

        // Create wrappers
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
        require(length < 32, "string too long");

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
