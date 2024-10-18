pragma solidity ^0.8.0;

interface IRealitio {
    function getContentHash(bytes32 questionId) external view returns (bytes32);
    function getOpeningTS(bytes32 questionId) external view returns (uint32);
    function resultFor(bytes32 questionId) external view returns (bytes32);
}
