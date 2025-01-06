// SPDX-License-Identifier: GPL-3.0-or-later
// TODO: move all solidity files to latest version
pragma solidity ^0.8.20;

import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";

/// @notice FlatCFM is a type of Decision Market.
contract FlatCFM {
    // Decision market attributes:
    FlatCFMOracleAdapter public immutable oracleAdapter;
    IConditionalTokens public immutable conditionalTokens;
    // ConditionalTokens-specific attributes:
    bytes32 public immutable questionId;
    uint256 public immutable outcomeCount;
    bytes32 public immutable conditionId;

    constructor(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        uint256 _outcomeCount,
        bytes32 _questionId,
        bytes32 _conditionId
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        outcomeCount = _outcomeCount;
        questionId = _questionId;
        conditionId = _conditionId;
    }

    /// @notice A resolver must call submitAnswer on Reality then
    ///     resolve here.
    /// @dev `reportPayouts` requires that the condition is already
    ///     prepared and payouts aren't reported yet.
    // solhint-disable-next-line
    // See https://github.com/gnosis/conditional-tokens-contracts/blob/eeefca66eb46c800a9aaab88db2064a99026fde5/contracts/ConditionalTokens.sol#L75
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount + 1);
        uint256 numericAnswer = uint256(answer);

        if (oracleAdapter.isInvalid(answer) || numericAnswer == 0) {
            payouts[outcomeCount] = 1;
        } else {
            for (uint256 i = 0; i < outcomeCount; i++) {
                payouts[i] = (numericAnswer >> i) & 1;
            }
        }

        conditionalTokens.reportPayouts(questionId, payouts);
    }
}
