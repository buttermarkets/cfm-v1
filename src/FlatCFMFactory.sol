// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";
import "./FlatCFM.sol";
import "./ConditionalScalarMarket.sol";
import {FlatCFMQuestionParams, GenericScalarQuestionParams} from "./Types.sol";

contract FlatCFMFactory {
    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    event FlatCFMCreated(
        address indexed market,
        string roundName,
        address collateralToken,
        bytes32 conditionalQuestionId,
        bytes32 conditionalConditionId
    );
    // XXX add
    event ConditionalMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex, address collateralToken
    );
    /*,
        bytes32 conditionalQuestionId,
        bytes32 conditionalConditionId*/

    constructor(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;
    }

    // XXX break this down
    function createMarket(
        FlatCFMQuestionParams calldata _flatCFMQuestionParams,
        GenericScalarQuestionParams calldata _genericScalarQuestionParams,
        IERC20 _collateralToken
    ) external returns (FlatCFM) {
        uint256 outcomeCount = _flatCFMQuestionParams.outcomeNames.length;

        // 1. Ask decision market question.
        bytes32 cfmQuestionId = oracleAdapter.askDecisionQuestion(_flatCFMQuestionParams);

        // 2. Prepare ConditionalTokens condition.
        conditionalTokens.prepareCondition(address(oracleAdapter), cfmQuestionId, outcomeCount);
        bytes32 cfmConditionId = conditionalTokens.getConditionId(address(oracleAdapter), cfmQuestionId, outcomeCount);

        // 3. Deploy decision market.
        FlatCFM flatCFM = new FlatCFM(oracleAdapter, conditionalTokens, outcomeCount, cfmQuestionId, cfmConditionId);

        emit FlatCFMCreated(
            address(flatCFM), _flatCFMQuestionParams.roundName, address(_collateralToken), cfmQuestionId, cfmConditionId
        );

        // 4. Deploy nested conditional markets.
        for (uint256 outcomeIndex = 0; outcomeIndex < outcomeCount; outcomeIndex++) {
            // Must be <=25 to allow for -LONG & -SHORT suffixes
            require(bytes(_flatCFMQuestionParams.outcomeNames[outcomeIndex]).length <= 25, "outcome name too long");

            string calldata outcomeName = _flatCFMQuestionParams.outcomeNames[outcomeIndex];
            bytes32 decisionCollectionId = conditionalTokens.getCollectionId(0, cfmConditionId, 1 << outcomeIndex);

            // 4.1. Ask conditional market question.
            bytes32 conditionalQuestionId = oracleAdapter.askMetricQuestion(_genericScalarQuestionParams, outcomeName);

            // 4.2. Prepare ConditionalTokens condition.
            conditionalTokens.prepareCondition(address(this), conditionalQuestionId, 2);
            bytes32 conditionalConditionId = conditionalTokens.getConditionId(address(this), conditionalQuestionId, 2);

            // 4.3. Deploy Long/Short ERC20s. Short index: 0.
            WrappedConditionalTokensData memory wrappedCTData = deployWrappedConditionalTokens(
                outcomeName, _collateralToken, decisionCollectionId, conditionalConditionId
            );

            // 4.3. Deploy conditional market.
            ConditionalScalarMarket csm = new ConditionalScalarMarket(
                oracleAdapter,
                conditionalTokens,
                wrapped1155Factory,
                ConditionalScalarCTParams({
                    questionId: conditionalQuestionId,
                    conditionId: conditionalConditionId,
                    parentCollectionId: decisionCollectionId,
                    collateralToken: _collateralToken
                }),
                ScalarParams({
                    minValue: _genericScalarQuestionParams.scalarParams.minValue,
                    maxValue: _genericScalarQuestionParams.scalarParams.maxValue
                }),
                wrappedCTData
            );

            emit ConditionalMarketCreated(
                address(flatCFM),
                address(csm),
                outcomeIndex,
                // XXX add outcomeName
                address(_collateralToken) /*, conditionalQuestionId, conditionalConditionId*/
            );
        }

        return flatCFM;
    }

    function deployWrappedConditionalTokens(
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
        uint256 shortPositionId = conditionalTokens.getPositionId(
            collateralToken,
            // Collection: condition, joint with decision outcome, 2nd slot.
            conditionalTokens.getCollectionId(
                // Parent collection: the corresponding decision outcome.
                decisionCollectionId,
                conditionalConditionId,
                1 // 1 << 0
            )
        );
        uint256 longPositionId = conditionalTokens.getPositionId(
            collateralToken,
            // Collection: condition, joint with decision outcome, 2nd slot.
            conditionalTokens.getCollectionId(
                // Parent collection: the corresponding decision outcome.
                decisionCollectionId,
                conditionalConditionId,
                2 // 1 << 1
            )
        );
        IERC20 wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPositionId, shortData);
        IERC20 wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPositionId, longData);

        return WrappedConditionalTokensData({
            shortData: shortData,
            longData: longData,
            shortPositionId: shortPositionId,
            longPositionId: longPositionId,
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
