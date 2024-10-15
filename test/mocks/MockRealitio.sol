pragma solidity ^0.8.0;

import "../../src/IRealitio.sol";

contract MockRealitio is IRealitio {
    mapping(address => bool) public owners;
    mapping(bytes32 => bytes32) private contentHashes;
    mapping(bytes32 => uint32) private openingTimestamps;
    mapping(bytes32 => bytes32) private results;
    mapping(bytes32 => uint32) private timeouts;

    constructor() {
        owners[msg.sender] = true;
    }

    modifier onlyOwners() {
        require(owners[msg.sender], "Only owner can call this function");
        _;
    }

    function addOwner(address newOwner) external onlyOwners {
        owners[newOwner] = true;
    }

    function removeOwner(address ownerToRemove) external onlyOwners {
        require(msg.sender != ownerToRemove, "Owner cannot remove themselves");
        owners[ownerToRemove] = false;
    }

    function getContentHash(bytes32 questionId) external view returns (bytes32) {
        return contentHashes[questionId];
    }

    function getOpeningTS(bytes32 questionId) external view returns (uint32) {
        return openingTimestamps[questionId];
    }

    function resultFor(bytes32 questionId) external view returns (bytes32) {
        return results[questionId];
    }

    function resultForOnceSettled(bytes32 questionId) external view returns (bytes32) {
        return results[questionId];
    }

    function setContentHash(bytes32 questionId, bytes32 contentHash) external onlyOwners {
        contentHashes[questionId] = contentHash;
    }

    function setOpeningTS(bytes32 questionId, uint32 openingTS) external onlyOwners {
        openingTimestamps[questionId] = openingTS;
    }

    function setResult(bytes32 questionId, bytes32 result) external onlyOwners {
        results[questionId] = result;
    }

    function getTimeout(bytes32 questionId) external view returns (uint32) {
        return timeouts[questionId];
    }

    function setTimeout(bytes32 questionId, uint32 timeout) external onlyOwners {
        timeouts[questionId] = timeout;
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
        // Mock implementation - could return a deterministic hash or store question details
        bytes32 questionId =
            keccak256(abi.encodePacked(template_id, question, arbitrator, timeout, opening_ts, nonce, min_bond));
        timeouts[questionId] = timeout;
        openingTimestamps[questionId] = opening_ts;
        return questionId;
    }
}
