// SPDX-License-Identifier: GPL-3.0-or-later
// TODO: move all solidity files to latest version
pragma solidity 0.8.28;

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
    string public metadatUri;

    constructor(
        FlatCFMOracleAdapter _oracleAdapter,
        IConditionalTokens _conditionalTokens,
        uint256 _outcomeCount,
        bytes32 _questionId,
        bytes32 _conditionId,
        string memory _metadatUri
    ) {
        oracleAdapter = _oracleAdapter;
        conditionalTokens = _conditionalTokens;
        outcomeCount = _outcomeCount;
        questionId = _questionId;
        conditionId = _conditionId;
        metadatUri = _metadatUri;
    }

    /// @notice A resolver must call submitAnswer on Reality then
    ///     resolve here.
    /// @dev `reportPayouts` requires that the condition is already
    ///     prepared and payouts aren't reported yet.
    // solhint-disable-next-line
    // See https://github.com/gnosis/conditional-tokens-contracts/blob/eeefca66eb46c800a9aaab88db2064a99026fde5/contracts/ConditionalTokens.sol#L75
    function resolve() external {
        oracleAdapter.reportDecisionPayouts(conditionalTokens, questionId, outcomeCount);
    }
}
