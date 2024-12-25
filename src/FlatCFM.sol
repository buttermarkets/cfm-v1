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

    // XXX keep? useless if this can be checked through ConditionalTokens.
    // State attributes:
    //bool public isResolved;

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

    // Process for a resolver: call submitAnswer on Reality then resolve here.
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount);

        // TODO: test the invalid case.
        if (!oracleAdapter.isInvalid(answer)) {
            uint256 numericAnswer = uint256(answer);

            for (uint256 i = 0; i < outcomeCount; i++) {
                payouts[i] = (numericAnswer >> i) & 1;
            }
        }

        // `reportPayouts` requires that the condition is already prepared and
        // payouts aren't reported yet.
        conditionalTokens.reportPayouts(questionId, payouts);
    }
}
