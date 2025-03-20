// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";

/// @dev This is based on the cfm-v1-subgraph results when fetching a list of
/// conditionalScalarMarkets.
abstract contract CSMJsonParser is Script {
    /// @dev Matches the JSON structure exactly, so decoding works.
    struct TokenAddress {
        address id;
    }

    struct PairAddress {
        address id;
    }

    struct Market {
        address id;
        TokenAddress shortToken;
        TokenAddress longToken;
        TokenAddress invalidToken;
        PairAddress pair;
    }

    function _parseAllMarkets(string memory json) public pure returns (Market[] memory) {
        // We'll assume there's some upper bound. 9999 is arbitrary, but stops infinite loops.
        // We'll collect results in a temporary fixed-size array, then slice to actual length.
        Market[] memory temp = new Market[](9999);
        uint256 count = 0;

        for (uint256 i = 0; i < 9999; i++) {
            string memory base = string.concat(".data.conditionalScalarMarkets[", vm.toString(i), "]");

            // If this fails, we've gone past the end of the array. Break the loop.
            try vm.parseJsonAddress(json, string.concat(base, ".id")) returns (address marketId) {
                Market memory m;
                m.id = marketId;
                m.shortToken.id = vm.parseJsonAddress(json, string.concat(base, ".shortToken.id"));
                m.longToken.id = vm.parseJsonAddress(json, string.concat(base, ".longToken.id"));
                m.invalidToken.id = vm.parseJsonAddress(json, string.concat(base, ".invalidToken.id"));
                m.pair.id = vm.parseJsonAddress(json, string.concat(base, ".pair.id"));
                temp[count++] = m;
            } catch {
                break;
            }
        }

        // Trim to actual length
        Market[] memory markets = new Market[](count);
        for (uint256 j = 0; j < count; j++) {
            markets[j] = temp[j];
        }
        return markets;
    }

    function _generatePartitionArray(uint256 outcomeCount) public pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }

    function _generatePartitionArrayString(uint256 outcomeCount) internal pure returns (string memory) {
        string memory partitionArray = "[";

        for (uint256 i = 0; i < outcomeCount; i++) {
            if (i > 0) {
                partitionArray = string.concat(partitionArray, ",");
            }
            partitionArray = string.concat(partitionArray, vm.toString(1 << i));
        }

        return string.concat('"', partitionArray, "]", '"');
    }
}
