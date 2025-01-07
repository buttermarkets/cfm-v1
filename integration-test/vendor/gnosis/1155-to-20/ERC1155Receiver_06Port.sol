// SPDX-License-Identifier: GPL-3.0-or-later
// Origin: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.2.0/contracts/token/ERC1155/ERC1155Receiver.sol
// Note: This contract is a port of the original work, with minor
// modifications for compatibility with the latest EVM and toolchain.
// The version of openzeppelin-contracts matches with
// Wrapped1155Factory.

pragma solidity 0.8.28;

import "@openzeppelin-contracts/token/ERC1155/IERC1155Receiver.sol";
import "./ERC165_06Port.sol";

/**
 * @dev _Available since v3.1._
 */
abstract contract ERC1155Receiver_06Port is ERC165_06Port, IERC1155Receiver {
    constructor() {
        _registerInterface(
            IERC1155Receiver.onERC1155Received.selector ^ IERC1155Receiver.onERC1155BatchReceived.selector
        );
    }
}
