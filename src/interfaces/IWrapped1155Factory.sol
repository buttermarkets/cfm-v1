// SPDX-License-Identifier: MIT
// TODO: either rm or move Wrapped1155Factory out of this codebase.
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IWrapped1155Factory {
    function requireWrapped1155(
        /*IERC1155*/
        address multiToken,
        uint256 tokenId,
        bytes calldata data
    ) external /*Wrapped1155*/ returns (IERC20);

    function unwrap(
        /*IERC1155*/
        address multiToken,
        uint256 tokenId,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external;
}
