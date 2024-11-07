// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../IRealitio.sol";
import "./interfaces/IOracle.sol";
import "./ConditionalScalarMarket.sol";

// Employing the adapter software-design-pattern here. The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

bytes32 constant REALITY_INVALID_RESULT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

enum RealityTemplate {
    Boolean,
    Integer,
    SingleSelect,
    MultiSelect,
    DateTime
}

contract OracleAdapter is IOracle {
    IRealitio public immutable oracle;

    ConditionalScalarMarket public immutable csm;

    constructor(IRealitio _oracle, ConditionalScalarMarket _csm) {
        oracle = _oracle;
        csm = _csm;
    }

    function encodeScalarQuestion(string memory question) public pure returns (string memory) {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        return string(abi.encodePacked(question, separator, "funding", separator, "en"));
    }

    function encodeMultiCategoricalQuestion(string memory question) public pure returns (string memory) {
        revert("Not implemented yet");
    }

    function askQuestion() public {
        revert("Not implemented yet");
    }

    function resolveMultiCategoricalMarket(bytes32 questionId, uint256 numOutcomes) internal {
        // TODO Validate questionID
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](numOutcomes + 1);

        if (answer == uint256(REALITY_INVALID_RESULT)) {
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

        csm.conditionalTokens().reportPayouts(questionId, payouts);
    }

    function resolveScalarMarket(bytes32 questionId, uint256 low, uint256 high) internal {
        // TODO Validate questionID
        uint256 answer = uint256(oracle.resultForOnceSettled(questionId));
        uint256[] memory payouts = new uint256[](3);

        if (answer == uint256(REALITY_INVALID_RESULT)) {
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

        csm.conditionalTokens().reportPayouts(questionId, payouts);
    }
}
