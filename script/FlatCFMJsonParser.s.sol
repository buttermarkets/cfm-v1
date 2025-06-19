// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import "src/Types.sol";

/// @dev Shared JSON parsing functions for FlatCFM creation scripts
abstract contract FlatCFMJsonParser is Script {
    // Fallback JSON file path
    string constant DEFAULT_CONFIG_FILE_PATH = "./flatcfm-config.json";

    /**
     * @dev Reads `MARKET_CONFIG_FILE` from env if present, otherwise returns DEFAULT_CONFIG_FILE_PATH
     */
    function _getJsonFilePath() public view returns (string memory) {
        string memory path;
        try vm.envString("MARKET_CONFIG_FILE") returns (string memory envPath) {
            path = envPath;
        } catch {
            path = DEFAULT_CONFIG_FILE_PATH;
        }
        return path;
    }

    function _parseFactoryAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".factoryAddress");
    }

    function _parseOracleAdapterAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".oracleAdapterAddress");
    }

    function _parseDecisionTemplateId(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".decisionTemplateId");
    }

    function _parseMetricTemplateId(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".metricTemplateId");
    }

    /// @dev Reads `FlatCFMQuestionParams` from JSON
    function _parseFlatCFMQuestionParams(string memory json) public pure returns (FlatCFMQuestionParams memory) {
        // outcomeNames is an array of strings
        bytes memory outcomeNamesRaw = vm.parseJson(json, ".outcomeNames");
        string[] memory outcomeNames = abi.decode(outcomeNamesRaw, (string[]));

        uint256 openingTimeDecision = vm.parseJsonUint(json, ".openingTimeDecision");
        require(openingTimeDecision <= type(uint32).max, "openingTime overflow");

        return FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: uint32(openingTimeDecision)});
    }

    /// @dev Reads `GenericScalarQuestionParams` from JSON
    function _parseGenericScalarQuestionParams(string memory json)
        public
        pure
        returns (GenericScalarQuestionParams memory)
    {
        // minValue & maxValue
        uint256 minValue = vm.parseJsonUint(json, ".minValue");
        uint256 maxValue = vm.parseJsonUint(json, ".maxValue");

        // openingTime for the metric
        uint256 openingTimeMetric = vm.parseJsonUint(json, ".openingTimeMetric");
        require(openingTimeMetric <= type(uint32).max, "openingTime overflow");

        return GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: uint32(openingTimeMetric)
        });
    }

    /// @dev Reads the collateral token address from JSON
    function _parseCollateralAddress(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".collateralToken");
    }

    function _parseMetadataUri(string memory json) public pure returns (string memory) {
        return vm.parseJsonString(json, ".metadataUri");
    }

    /// @dev Reads default invalid payouts from JSON. Only used by InvalidlessFlatCFM.
    function _parseDefaultInvalidPayouts(string memory json) public pure returns (uint256[2] memory) {
        bytes memory payoutsRaw = vm.parseJson(json, ".defaultPayouts");
        uint256[] memory payouts = abi.decode(payoutsRaw, (uint256[]));
        require(payouts.length == 2, "defaultPayouts must have exactly 2 values");
        return [payouts[0], payouts[1]];
    }

    /// @dev Reads slippage percentage from JSON
    function _parseSlippagePct(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".slippagePct");
    }

    /// @dev Reads Uniswap V2 Router address from JSON
    function _parseUniswapV2Router(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".uniswapV2Router");
    }

    /// @dev Reads Uniswap V2 Factory address from JSON
    function _parseUniswapV2Factory(string memory json) public pure returns (address) {
        return vm.parseJsonAddress(json, ".uniswapV2Factory");
    }

    /// @dev Reads deposit amount from JSON
    function _parseDepositAmount(string memory json) public pure returns (uint256) {
        return vm.parseJsonUint(json, ".depositAmount");
    }
}
