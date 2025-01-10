// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "src/interfaces/IWrapped1155Factory.sol";

contract DummyWrapped1155Factory is IWrapped1155Factory {
    function requireWrapped1155(IERC1155, uint256, bytes calldata) external pure returns (IERC20) {
        return IERC20(address(0xDEAD));
    }

    function unwrap(IERC1155, uint256, uint256, address, bytes calldata) external {}
}
