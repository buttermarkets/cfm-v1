// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOracle {
    function encodeScalarQuestion(string memory question) external pure returns (string memory);
    function encodeMultiCategoricalQuestion(string memory question) external pure returns (string memory);
    function askQuestion() external;
}
