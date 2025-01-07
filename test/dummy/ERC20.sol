// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

contract DummyERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

//contract ERC20Mock is IERC20 {
//    string public name;
//    string public symbol;
//    uint8 public decimals = 18;
//
//    uint256 total;
//    mapping(address => uint256) private _balances;
//    mapping(address => mapping(address => uint256)) private _allowance;
//
//    constructor(string memory _name, string memory _symbol) {
//        name = _name;
//        symbol = _symbol;
//    }
//
//    function totalSupply() external view returns (uint256) {
//        return total;
//    }
//
//    function balanceOf(address account) public view returns (uint256) {
//        return _balances[account];
//    }
//
//    function transfer(address to, uint256 amount) external returns (bool) {
//        _balances[msg.sender] -= amount;
//        _balances[to] += amount;
//        return true;
//    }
//
//    function allowance(address owner, address spender) external view returns (uint256) {
//        return _allowance[owner][spender];
//    }
//
//    function approve(address spender, uint256 amount) external returns (bool) {
//        _allowance[msg.sender][spender] = amount;
//        return true;
//    }
//
//    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
//        _allowance[from][msg.sender] -= amount;
//        _balances[from] -= amount;
//        _balances[to] += amount;
//        return true;
//    }
//
//    function mint(address to, uint256 amount) external {
//        _balances[to] += amount;
//        total += amount;
//    }
//}
