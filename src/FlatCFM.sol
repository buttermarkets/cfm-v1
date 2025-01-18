// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "./interfaces/IConditionalTokens.sol";
import "./FlatCFMOracleAdapter.sol";

/// @title FlatCFM
/// @notice A "flat" decision market contract that uses a bitmask-based resolution for multiple outcomes.
contract FlatCFM {
    /// @notice Oracle adapter responsible for question handling.
    FlatCFMOracleAdapter public oracleAdapter;

    /// @notice Gnosis Conditional Tokens contract.
    IConditionalTokens public conditionalTokens;

    /// @notice ID of the underlying question used to finalize the condition in the conditional tokens contract.
    bytes32 public questionId;

    /// @notice Number of outcomes (excluding the extra 'Invalid' slot).
    uint256 public outcomeCount;

    /// @notice Metadata URI for referencing external info or front-ends.
    string public metadataUri;

    /// @dev Initialization guard.
    bool public initialized;

    error AlreadyInitialized();

    /// @notice Initializes the FlatCFM contract (called once by the factory).
    /// @param _oracleAdapter Adapter to ask questions and get answers on the
    ///                       underlying oracle.
    /// @param _conditionalTokens Gnosis Conditional Tokens contract address.
    /// @param _outcomeCount Number of outcomes (excluding 'Invalid').
    /// @param _questionId The question ID used in the conditional tokens condition.
    /// @param _metadataUri Metadata URI.
    function initialize(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        uint256 _outcomeCount,
        bytes32 _questionId,
        string memory _metadataUri
    ) external {
        if (initialized) revert AlreadyInitialized();
        initialized = true;

        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        outcomeCount = _outcomeCount;
        questionId = _questionId;
        metadataUri = _metadataUri;
    }

    /// @notice Resolves the condition in the conditional tokens contract based on the oracle answer.
    /// @dev Uses bitmask logic: each bit in the numeric answer indicates whether
    ///      that outcome is true (1) or false (0). The extra 'Invalid' slot is used
    ///      if the answer is out of range or flagged invalid.
    function resolve() external {
        bytes32 answer = oracleAdapter.getAnswer(questionId);
        uint256[] memory payouts = new uint256[](outcomeCount + 1);
        uint256 numericAnswer = uint256(answer);

        if (oracleAdapter.isInvalid(answer) || numericAnswer == 0) {
            // 'Invalid' receives full payout
            payouts[outcomeCount] = 1;
        } else {
            // Each bit (i-th) in numericAnswer indicates if outcome i is 1 or 0
            for (uint256 i = 0; i < outcomeCount; i++) {
                payouts[i] = (numericAnswer >> i) & 1;
            }
        }
        conditionalTokens.reportPayouts(questionId, payouts);
    }
}
