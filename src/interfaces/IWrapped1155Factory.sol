// SPDX-License-Identifier: MIT
// Maps to: https://github.com/gnosis/1155-to-20/blob/master/contracts/Wrapped1155Factory.sol
pragma solidity ^0.8.20;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155.sol";

interface IWrapped1155Factory {
    function requireWrapped1155(IERC1155 multiToken, uint256 tokenId, bytes calldata data) external returns (IERC20);

    function unwrap(IERC1155 multiToken, uint256 tokenId, uint256 amount, address recipient, bytes calldata data)
        external;
}
