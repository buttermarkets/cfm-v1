// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import "src/libs/String31.sol";

contract String31Test is Test {
    function testEmptyString() public pure {
        bytes32 encoded = String31.toString31("");
        uint256 len = _decodeLength(encoded);
        bytes32 content = _stripLengthByte(encoded);

        assertEq(len, 0);
        assertEq(content, bytes32(0));
    }

    function testShortString() public pure {
        string memory input = "Hello";
        bytes32 encoded = String31.toString31(input);
        uint256 len = _decodeLength(encoded);
        bytes32 content = _stripLengthByte(encoded);

        assertEq(len, 5);

        // Compare with first 5 bytes of "Hello", zero-padded to 32.
        bytes32 expected;
        assembly {
            expected := mload(add(input, 0x20))
        }
        // Mask trailing unused bytes
        expected = expected & (bytes32(type(uint256).max << ((32 - len) << 3)));

        assertEq(content, expected);
    }

    function testMaxStringLength() public pure {
        // Exactly 31 characters
        string memory input = "1234567890123456789012345678901";
        bytes32 encoded = String31.toString31(input);
        uint256 len = _decodeLength(encoded);

        assertEq(len, 31);
    }

    function testTooLongReverts() public {
        // 32 characters
        string memory input = "12345678901234567890123456789012";
        vm.expectRevert(abi.encodeWithSelector(String31.InvalidString31Length.selector, input));
        String31.toString31(input);
    }

    // Decodes the stored length from the last byte (length*2).
    function _decodeLength(bytes32 data) internal pure returns (uint256) {
        return (uint256(data) & 0xFF) >> 1;
    }

    // Strips out the last byte used for length, leaving only content bytes.
    function _stripLengthByte(bytes32 data) internal pure returns (bytes32) {
        return data & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00;
    }
}
