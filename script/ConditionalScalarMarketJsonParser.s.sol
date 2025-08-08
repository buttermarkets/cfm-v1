// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";

/// @dev Shared JSON parsing functions for ConditionalScalarMarket and InvalidlessConditionalScalarMarket creation scripts
abstract contract ConditionalScalarMarketJsonParser is Script {
    // Fallback JSON file path
    string constant DEFAULT_CONFIG_FILE_PATH = "./icsm.config.json";

    /**
     * @dev Reads `MARKET_CONFIG_FILE` from env if present, otherwise returns DEFAULT_CONFIG_FILE_PATH
     */
    function _getJsonFilePath() public view virtual returns (string memory) {
        string memory path;
        try vm.envString("MARKET_CONFIG_FILE") returns (string memory envPath) {
            path = envPath;
        } catch {
            path = DEFAULT_CONFIG_FILE_PATH;
        }
        return path;
    }

    function _parseOracleAdapterAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".oracleAdapterAddress");
    }

    function _parseConditionalTokensAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".conditionalTokens");
    }

    function _parseWrapped1155FactoryAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".wrapped1155Factory");
    }

    function _parseCollateralAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".collateralToken");
    }

    function _parseTemplateId(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".templateId");
    }

    function _parseOutcomeName(string memory json) public pure returns (string memory) {
        return vm.parseJsonString(json, ".outcomeName");
    }

    function _parseMinValue(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".minValue");
    }

    function _parseMaxValue(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".maxValue");
    }

    function _parseOpeningTime(string memory json) public pure returns (uint32) {
        uint256 openingTime = vm.parseJsonUint(json, ".openingTime");
        require(openingTime <= type(uint32).max, "openingTime overflow");
        return uint32(openingTime);
    }

    /// @dev Reads default invalid payouts from JSON. Only used by InvalidlessConditionalScalarMarket.
    function _parseDefaultInvalidPayouts(string memory json) public pure returns (uint256[2] memory) {
        bytes memory payoutsRaw = vm.parseJson(json, ".defaultInvalidPayouts");
        uint256[] memory payouts = abi.decode(payoutsRaw, (uint256[]));
        require(payouts.length == 2, "defaultInvalidPayouts must have exactly 2 values");
        return [payouts[0], payouts[1]];
    }

    /// @dev Parse parent collection ID for nested markets (optional)
    function _parseParentCollectionId(string memory json) public pure returns (bytes32) {
        try vm.parseJsonBytes32(json, ".parentCollectionId") returns (bytes32 parentCollectionId) {
            return parentCollectionId;
        } catch {
            return bytes32(0);
        }
    }

    /// @dev Parse whether to include invalid outcome (for standard ConditionalScalarMarket)
    function _parseIncludeInvalid(string memory json) public pure returns (bool) {
        try vm.parseJsonBool(json, ".includeInvalid") returns (bool includeInvalid) {
            return includeInvalid;
        } catch {
            return true; // Default to true for standard ConditionalScalarMarket
        }
    }
}
