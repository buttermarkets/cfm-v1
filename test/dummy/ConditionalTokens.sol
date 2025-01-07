// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import "src/interfaces/IConditionalTokens.sol";

contract DummyConditionalTokens is IConditionalTokens {
    mapping(address => mapping(uint256 => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApproval;
    mapping(bytes32 => uint256[]) public override payoutNumerators;
    mapping(bytes32 => uint256) public override payoutDenominator;

    function supportsInterface(bytes4 interfaceID) external pure override returns (bool) {
        return interfaceID == type(IERC165).interfaceId || interfaceID == type(IERC1155).interfaceId
            || interfaceID == type(IConditionalTokens).interfaceId;
    }

    function balanceOf(address account, uint256 id) public view override returns (uint256) {
        return _balances[account][id];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        override
        returns (uint256[] memory)
    {
        require(accounts.length == ids.length, "length mismatch");
        uint256[] memory result = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            result[i] = _balances[accounts[i]][ids[i]];
        }
        return result;
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApproval[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address account, address operator) public view override returns (bool) {
        return _operatorApproval[account][operator];
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        override
    {
        require(to != address(0), "zero address");
        require(from == msg.sender || _operatorApproval[from][msg.sender], "not authorized");
        require(_balances[from][id] >= amount, "insufficient");
        _balances[from][id] -= amount;
        _balances[to][id] += amount;
        data;
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external override {
        require(to != address(0), "zero address");
        require(ids.length == amounts.length, "length mismatch");
        require(from == msg.sender || _operatorApproval[from][msg.sender], "not authorized");
        for (uint256 i = 0; i < ids.length; i++) {
            require(_balances[from][ids[i]] >= amounts[i], "insufficient");
            _balances[from][ids[i]] -= amounts[i];
            _balances[to][ids[i]] += amounts[i];
        }
        data;
    }

    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount) external override {
        require(outcomeSlotCount <= 256, "too many outcome slots");
        require(outcomeSlotCount > 1, "there should be more than one outcome slot");
        bytes32 conditionId = keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
        require(payoutNumerators[conditionId].length == 0, "condition already prepared");
        payoutNumerators[conditionId] = new uint256[](outcomeSlotCount);
    }

    address public _test_reportPayouts_caller;

    function reportPayouts(bytes32, uint256[] calldata) external override {
        _test_reportPayouts_caller = msg.sender;
    }

    function splitPosition(IERC20, bytes32, bytes32, uint256[] calldata, uint256) external override {}
    function mergePositions(IERC20, bytes32, bytes32, uint256[] calldata, uint256) external override {}
    function redeemPositions(IERC20, bytes32, bytes32, uint256[] calldata) external override {}

    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        external
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    function getCollectionId(bytes32, bytes32, uint256) external pure override returns (bytes32) {
        return keccak256("colId");
    }

    function getPositionId(IERC20, bytes32) external pure override returns (uint256) {
        return uint256(keccak256("posId"));
    }

    function getOutcomeSlotCount(bytes32 conditionId) external view returns (uint256) {
        return payoutNumerators[conditionId].length;
    }

    function _mint(address to, uint256 id, uint256 amount) internal {
        _balances[to][id] += amount;
    }

    function _burn(address from, uint256 id, uint256 amount) internal {
        require(_balances[from][id] >= amount, "burn exceeds balance");
        _balances[from][id] -= amount;
    }
}
