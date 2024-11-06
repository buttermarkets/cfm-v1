// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../IRealitio.sol";
import "./ConditionalFundingMarket.sol";

// Employing the adapter software-design-pattern here. The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

/// @dev Template for scalar and multi scalar markets.
uint256 constant REALITY_UINT_TEMPLATE = 1;
/// @dev Template for categorical markets.
uint256 constant REALITY_SINGLE_SELECT_TEMPLATE = 2;
/// @dev Template for multi categorical markets.
uint256 constant REALITY_MULTI_SELECT_TEMPLATE = 3;
bytes32 constant INVALID_RESULT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;


interface ClientInterface {
}

interface OracleInterface is IRealitio {
    function askQuestionWithMinBond(
        uint256 template_id,
        string memory question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 min_bond
    ) external payable returns (bytes32);
    function resultForOnceSettled(bytes32 question_id) external view returns (bytes32);
    function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous) external payable;
    function getContentHash(bytes32 questionId) external view returns (bytes32);
    function getOpeningTS(bytes32 questionId) external view returns (uint32);
    function resultFor(bytes32 questionId) external view returns (bytes32);
}

contract OracleAdapter is ClientInterface, OracleInterface {
    IRealitio public immutable oracle;

    ConditionalFundingMarket public immutable cfm;

    constructor(IRealitio _oracle, ConditionalFundingMarket _cfm) {
        oracle = _oracle;
        cfm = _cfm;
    }

    function getContentHash(bytes32 questionId) external view override(OracleInterface) returns (bytes32) {
        return oracle.getContentHash(questionId);
    }

    function getOpeningTS(bytes32 questionId) external view override(OracleInterface) returns (uint32) {
        return oracle.getOpeningTS(questionId);
    }

    function resultFor(bytes32 questionId) external view override(OracleInterface) returns (bytes32) {
        return oracle.resultFor(questionId);
    }

    function askQuestionWithMinBond(
        uint256 template_id,
        string memory question,
        address arbitrator,
        uint32 timeout,
        uint32 opening_ts,
        uint256 nonce,
        uint256 min_bond
    ) external payable returns (bytes32) {
        revert("Not implemented");
    }

    function resultForOnceSettled(bytes32 question_id) external view returns (bytes32) {
        return oracle.resultFor(question_id);
    }

    function submitAnswer(bytes32 question_id, bytes32 answer, uint256 max_previous) external payable {
        revert("Not implemented");
    }

    function resolve(bytes32 questionsId, uint256 numOutcomes, uint256 templateId, uint256 low, uint256 high)
        external
    {
        // questionId must be a hash of all the values used to resolve a market, this way if an attacker tries to resolve a fake market by changing some value its questionId will not match the id of a valid market.
        bytes32 questionId = keccak256(abi.encode(questionsId, numOutcomes, templateId, low, high));

        if (templateId == REALITY_SINGLE_SELECT_TEMPLATE) {
            revert("Not implemented");
        }

        if (templateId == REALITY_MULTI_SELECT_TEMPLATE) {
            revert("Not implemented");
        }

        resolveScalarMarket(questionId, low, high);
    }

    /// @dev Resolves to invalid if the answer is invalid or the result is greater than the amount of outcomes.
    /// @param questionId Conditional Tokens questionId.
    /// @param numOutcomes The number of outcomes, excluding the INVALID_RESULT outcome.
    function resolveCategoricalMarket(bytes32 questionId, uint256 numOutcomes) internal {
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](numOutcomes + 1);

        if (answer == uint256(INVALID_RESULT) || answer >= numOutcomes) {
            // the last outcome is INVALID_RESULT.
            payouts[numOutcomes] = 1;
        } else {
            payouts[answer] = 1;
        }

        cfm.conditionalTokens().reportPayouts(questionId, payouts);
    }

    /// @dev Resolves to invalid if the answer is invalid or all the results are zero.
    /// @param questionId Conditional Tokens questionId.
    /// @param numOutcomes The number of outcomes, excluding the INVALID_RESULT outcome.
    function resolveMultiCategoricalMarket(bytes32 questionId, uint256 numOutcomes) internal {
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](numOutcomes + 1);

        if (answer == uint256(INVALID_RESULT)) {
            // the last outcome is INVALID_RESULT.
            payouts[numOutcomes] = 1;
        } else {
            bool allZeroes = true;

            for (uint256 i = 0; i < numOutcomes; i++) {
                payouts[i] = (answer >> i) & 1;
                allZeroes = allZeroes && payouts[i] == 0;
            }

            if (allZeroes) {
                // invalid result.
                payouts[numOutcomes] = 1;
            }
        }

        cfm.conditionalTokens().reportPayouts(questionId, payouts);
    }

    /// @dev Resolves to invalid if the answer is invalid.
    /// @param questionId Conditional Tokens questionId.
    /// @param low Lower bound.
    /// @param high Upper bound.
    function resolveScalarMarket(bytes32 questionId, uint256 low, uint256 high) internal {
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](3);

        if (answer == uint256(INVALID_RESULT)) {
            // the last outcome is INVALID_RESULT.
            payouts[2] = 1;
        } else if (answer <= low) {
            payouts[0] = 1;
        } else if (answer >= high) {
            payouts[1] = 1;
        } else {
            payouts[0] = high - answer;
            payouts[1] = answer - low;
        }

        cfm.conditionalTokens().reportPayouts(questionId, payouts);
    }
}
