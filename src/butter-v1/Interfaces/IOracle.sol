// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOracle {
    function encodeScalarQuestion(string memory question, string memory conditionOutcomeName) external pure returns (string memory);
    function encodeMultiCategoricalQuestion(string memory question, string[] calldata outcomes)
        external
        pure
        returns (string memory);
    function prepareQuestion(
        address arbitrator,
        string memory encodedQuestion,
        uint256 templateID,
        uint32 openingTime,
        uint32 questionTimeout,
        uint256 minBond
    ) external returns (bytes32);
    function resultForOnceSettled(bytes32 questionID) external view returns (bytes32);

    function getInvalidValue() external pure returns (bytes32);
}
