// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

library String31 {
    error InvalidString31Length(string value);

    /// @dev Encodes a short string (less than than 31 bytes long) to leverage
    /// short string layout.
    /// <https://docs.soliditylang.org/en/v0.8.1/internals/layout_in_storage.html#bytes-and-string>
    /// From https://github.com/gnosis/1155-to-20/pull/4#discussion_r573630922
    function toString31(string memory value) internal pure returns (bytes32 encodedString) {
        uint256 length = bytes(value).length;
        if (length > 31) revert InvalidString31Length(value);

        // Read the right-padded string data, which is guaranteed to fit into a single
        // word because its length is less than 32.
        assembly {
            encodedString := mload(add(value, 0x20))
        }

        // Now mask the string data, this ensures that the bytes past the string length
        // are all 0s.
        bytes32 mask = bytes32(type(uint256).max << ((32 - length) << 3));
        encodedString = encodedString & mask;

        // Finally, set the least significant byte to be the hex length of the encoded
        // string, that is its byte-length times two.
        encodedString = encodedString | bytes32(length << 1);
    }
}
