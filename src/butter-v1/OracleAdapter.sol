// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../IRealitio.sol";
import "./interfaces/IOracle.sol";
import "./ConditionalScalarMarket.sol";

// Employing the adapter software-design-pattern here. The adapter component implements both client (CFM) interface
// and service (Reality) interface and translates incoming and outgoing calls between client and service.

enum RealityTemplate {
    Boolean,
    Integer,
    SingleSelect,
    MultiSelect,
    DateTime
}

contract OracleAdapter is IOracle {
    IRealitio public immutable oracle;

    constructor(IRealitio _oracle) {
        oracle = _oracle;
    }

    function encodeScalarQuestion(string memory question, string memory conditionOutcomeName)
        public
        pure
        returns (string memory)
    {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        // Replace %s placeholder with conditionOutcomeName
        bytes memory questionBytes = bytes(question);
        bytes memory nameBytes = bytes(conditionOutcomeName);
        bytes memory result = new bytes(questionBytes.length + nameBytes.length - 2); // -2 for %s

        uint256 j = 0;
        bool replaced = false;
        for (uint256 i = 0; i < questionBytes.length; i++) {
            if (i < questionBytes.length - 1 && questionBytes[i] == "%" && questionBytes[i + 1] == "s") {
                for (uint256 k = 0; k < nameBytes.length; k++) {
                    result[j++] = nameBytes[k];
                }
                i++; // Skip 's'
                replaced = true;
            } else {
                result[j++] = questionBytes[i];
            }
        }

        require(replaced, "Question must contain %s placeholder");
        string memory formattedQuestion = string(result);

        return string(abi.encodePacked(formattedQuestion, separator, "funding", separator, "en"));
    }

    function encodeMultiCategoricalQuestion(string memory question, string[] calldata outcomes)
        public
        pure
        returns (string memory)
    {
        bytes memory separator = abi.encodePacked(unicode"\u241f");

        bytes memory encodedOutcomes = abi.encodePacked('"', outcomes[0], '"');

        for (uint256 i = 1; i < outcomes.length; i++) {
            encodedOutcomes = abi.encodePacked(encodedOutcomes, ',"', outcomes[i], '"');
        }

        return string(abi.encodePacked(question, separator, encodedOutcomes, separator, "funding", separator, "en"));
    }

    function prepareQuestion(
        address arbitrator,
        string memory encodedQuestion,
        uint256 templateId,
        uint32 openingTime,
        uint32 questionTimeout,
        uint256 minBond
    ) public returns (bytes32) {
        bytes32 content_hash = keccak256(abi.encodePacked(templateId, openingTime, encodedQuestion));

        bytes32 question_id = keccak256(
            abi.encodePacked(
                content_hash, arbitrator, questionTimeout, minBond, address(oracle), address(this), uint256(0)
            )
        );

        if (oracle.getTimeout(question_id) != 0) {
            return question_id;
        }

        return oracle.askQuestionWithMinBond(
            templateId, encodedQuestion, arbitrator, questionTimeout, openingTime, 0, minBond
        );
    }

    function resultForOnceSettled(bytes32 questionID) public view returns (bytes32) {
        return oracle.resultForOnceSettled(questionID);
    }

    function getInvalidValue() public pure returns (bytes32) {
        return 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    }
}
