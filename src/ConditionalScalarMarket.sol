// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO: use explicit imports whenever clearer.
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./interfaces/IWrapped1155Factory.sol";
import "./interfaces/IConditionalTokens.sol";
import {CFMConditionalQuestionParams, ConditionalMarketCTParams} from "./QuestionTypes.sol";
import "./CFMOracleAdapter.sol";
import "./ConditionalMarket.sol";

contract ConditionalScalarMarket is ConditionalMarket, ERC1155Holder {
    // DecisionMarket generic params:
    CFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    IWrapped1155Factory public immutable wrapped1155Factory;

    // CondtionalMarket-specific params:
    uint256 public immutable minValue;
    uint256 public immutable maxValue;
    uint256 public immutable outcomeIndex;
    bytes32 public immutable parentConditionId;
    IERC20 public immutable collateralToken;

    // Initialized attributes:
    bytes32 public questionId;
    bytes32 public conditionId;
    bytes public shortData;
    bytes public longData;
    uint256 public shortPositionId;
    uint256 public longPositionId;
    IERC20 public wrappedShort;
    IERC20 public wrappedLong;

    // State attributes:
    bool public override isResolved;

    constructor(
        CFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        IWrapped1155Factory _wrapped1155Factory,
        CFMConditionalQuestionParams memory _conditionalQuestionParams,
        ConditionalMarketCTParams memory _conditionalTokensParams
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        wrapped1155Factory = _wrapped1155Factory;

        minValue = _conditionalQuestionParams.minValue;
        maxValue = _conditionalQuestionParams.maxValue;

        collateralToken = _conditionalTokensParams.collateralToken;
        outcomeIndex = _conditionalTokensParams.outcomeIndex;
        parentConditionId = _conditionalTokensParams.parentConditionId;

        initializeQuestion(_conditionalQuestionParams, _conditionalTokensParams);
        initializeCondition();
        initializeTokens(_conditionalTokensParams);
    }

    // TODO: Move initialization to factory call.
    function initializeQuestion(
        CFMConditionalQuestionParams memory _conditionalQuestionParams,
        ConditionalMarketCTParams memory _conditionalTokensParams
    ) private {
        questionId = oracleAdapter.askMetricQuestion(_conditionalQuestionParams, _conditionalTokensParams.outcomeName);
    }

    function initializeCondition() private {
        conditionalTokens.prepareCondition(address(this), questionId, 2);
        conditionId = conditionalTokens.getConditionId(address(this), questionId, 2);
    }

    function initializeTokens(ConditionalMarketCTParams memory _conditionalTokensParams) private {
        // Deploy Long/Short ERC20s. Short index: 0.
        shortData = abi.encodePacked(
            toString31(string.concat(_conditionalTokensParams.outcomeName, "-Short")),
            toString31(string.concat(_conditionalTokensParams.outcomeName, "-ST")),
            uint8(18)
        );
        longData = abi.encodePacked(
            toString31(string.concat(_conditionalTokensParams.outcomeName, "-Long")),
            toString31(string.concat(_conditionalTokensParams.outcomeName, "-LG")),
            uint8(18)
        );
        shortPositionId = conditionalTokens.getPositionId(
            collateralToken,
            // Collection: condition, joint with decision outcome, 2nd slot.
            conditionalTokens.getCollectionId(
                // Parent collection: the corresponding decision outcome.
                getDecisionCollectionId(),
                conditionId,
                1 // 1 << 0
            )
        );
        longPositionId = conditionalTokens.getPositionId(
            collateralToken,
            // Collection: condition, joint with decision outcome, 2nd slot.
            conditionalTokens.getCollectionId(
                // Parent collection: the corresponding decision outcome.
                getDecisionCollectionId(),
                conditionId,
                2 // 1 << 1
            )
        );
        // FIXME: is this type-bypassing really needed?
        wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPositionId, shortData);
        wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPositionId, longData);
    }

    /// @notice Reports payouts corresponding to the scalar value reported by
    /// the oracle. If the oracle value is invalid, report 50/50.
    function resolve() external override {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](2);

        // If the answer is invalid, no payouts are returned.
        // TODO: test all cases, including invalid. In invalid, the user should
        // still be able to merge positions.
        if (!oracleAdapter.isInvalid(answer)) {
            uint256 numericAnswer = uint256(answer);
            if (numericAnswer <= minValue) {
                payouts[0] = 1;
            } else if (numericAnswer >= maxValue) {
                payouts[1] = 1;
            } else {
                payouts[0] = maxValue - numericAnswer;
                payouts[1] = numericAnswer - minValue;
            }
        } else {
            payouts[0] = 1;
            payouts[1] = 1;
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }

    /// @notice Splits decision outcome into wrapped Long/Short.
    function split(uint256 amount) external {
        // User transfers decision outcome ERC1155 to this contract.
        conditionalTokens.safeTransferFrom(
            msg.sender,
            address(this),
            conditionalTokens.getPositionId(collateralToken, getDecisionCollectionId()),
            amount,
            ""
        );

        // Split position. Decision outcome ERC1155 are burnt. Conditional
        // Long/Short ERC1155 are minted to the contract.
        conditionalTokens.splitPosition(
            collateralToken, getDecisionCollectionId(), conditionId, discreetPartition(), amount
        );

        // Contract transfers Long/Short ERC1155 to wrapped1155Factory and
        // gets back Long/Short ERC20.
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), shortPositionId, amount, shortData
        );
        conditionalTokens.safeTransferFrom(address(this), address(wrapped1155Factory), longPositionId, amount, longData);

        // Contract transfers Long/Short ERC20 to user.
        require(wrappedShort.transfer(msg.sender, amount), "split short erc20 transfer failed");
        require(wrappedLong.transfer(msg.sender, amount), "split long erc20 transfer failed");
    }

    /// @notice Merges wrapped Long/Short back into decision outcome.
    function merge(uint256 amount) external {
        require(amount > 0, "amount must be positive");

        // User transfers Long/Short ERC20 to contract.
        require(wrappedShort.transferFrom(msg.sender, address(this), amount), "short token transfer failed");
        require(wrappedLong.transferFrom(msg.sender, address(this), amount), "long token transfer failed");

        // Contract transfers Long/Short ERC20 to wrapped1155Factory and gets
        // back Long/Short ERC1155.
        wrapped1155Factory.unwrap(conditionalTokens, shortPositionId, amount, address(this), shortData);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionId, amount, address(this), longData);

        // Merge position. Long/Short ERC1155 are burnt. Decision outcome
        // ERC1155 are minted.
        conditionalTokens.mergePositions(
            collateralToken, getDecisionCollectionId(), conditionId, discreetPartition(), amount
        );

        // Contract transfers decision outcome ERC1155 to user.
        conditionalTokens.safeTransferFrom(
            address(this),
            msg.sender,
            conditionalTokens.getPositionId(collateralToken, getDecisionCollectionId()),
            amount,
            ""
        );
    }

    /// @notice Redeems Long/Short positions after condition resolution.
    /// @param shortAmount Amount of Short tokens to redeem (can be 0).
    /// @param longAmount Amount of Long tokens to redeem (can be 0).
    function redeem(uint256 shortAmount, uint256 longAmount) external {
        uint256 den = conditionalTokens.payoutDenominator(conditionId);
        require(den > 0, "condition not resolved");

        // User transfers Long/Short ERC20 to contract.
        require(wrappedShort.transferFrom(msg.sender, address(this), shortAmount), "short token transfer failed");
        require(wrappedLong.transferFrom(msg.sender, address(this), longAmount), "long token transfer failed");

        // Contracts transfers Long/Short ERC20 to wrapped1155Factory and gets
        // back Long/Short ERC1155.
        wrapped1155Factory.unwrap(conditionalTokens, shortPositionId, shortAmount, address(this), shortData);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionId, longAmount, address(this), longData);

        uint256 decisionPositionId = conditionalTokens.getPositionId(collateralToken, getDecisionCollectionId());
        uint256 initialBalance = conditionalTokens.balanceOf(address(this), decisionPositionId);

        // Redeem positions. Long/Short ERC1155 are burnt. Decision outcome
        // ERC1155 are minted in proportion of payouts.
        conditionalTokens.redeemPositions(collateralToken, getDecisionCollectionId(), conditionId, discreetPartition());

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

    // From https://github.com/gnosis/1155-to-20/pull/4#discussion_r573630922
    /// @dev Encodes a short string (less than than 31 bytes long) as for storage as expected by Solidity.
    /// <https://docs.soliditylang.org/en/v0.8.1/internals/layout_in_storage.html#bytes-and-string>
    function toString31(string memory value) public pure returns (bytes32 encodedString) {
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

    function getDecisionCollectionId() private view returns (bytes32) {
        return conditionalTokens.getCollectionId(0, parentConditionId, 1 << outcomeIndex);
    }
}
