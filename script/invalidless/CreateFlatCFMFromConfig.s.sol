// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";

import "src/invalidless/InvalidlessFlatCFMFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";

contract CreateInvalidlessFlatCFMFromConfig is Script {
    // Fallback JSON file path
    string constant DEFAULT_CONFIG_FILE_PATH = "./flatcfm-config.json";

    function run() external {
        vm.startBroadcast();

        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        InvalidlessFlatCFMFactory factory = InvalidlessFlatCFMFactory(_parseFactoryAddress(jsonContent));
        FlatCFMOracleAdapter oracleAdapter = FlatCFMOracleAdapter(_parseOracleAdapterAddress(jsonContent));
        uint256 decisionTemplateId = _parseDecisionTemplateId(jsonContent);
        uint256 metricTemplateId = _parseMetricTemplateId(jsonContent);
        FlatCFMQuestionParams memory decisionQuestionParams = _parseFlatCFMQuestionParams(jsonContent);
        GenericScalarQuestionParams memory genericScalarQuestionParams = _parseGenericScalarQuestionParams(jsonContent);
        address collateralAddr = _parseCollateralAddress(jsonContent);
        string memory metadataUri = _parseMetadataUri(jsonContent);
        uint256[2] memory defaultInvalidPayouts = _parseDefaultPayouts(jsonContent);

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            IERC20(collateralAddr),
            metadataUri
        );
        console.log("Deployed FlatCFM at:", address(cfm));

        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            InvalidlessConditionalScalarMarket icsm = factory.createConditionalScalarMarket(cfm, defaultInvalidPayouts);
            console.log("Deployed InvalidlessConditionalScalarMarket at:", address(icsm));
        }

        vm.stopBroadcast();
    }

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

    /// @dev Reads default invalid payouts from JSON
    /// @return A fixed array of two uint256 values [shortPayout, longPayout]
    function _parseDefaultPayouts(string memory json) public pure returns (uint256[2] memory) {
        bytes memory payoutsRaw = vm.parseJson(json, ".defaultPayouts");
        uint256[] memory payouts = abi.decode(payoutsRaw, (uint256[]));
        require(payouts.length == 2, "defaultPayouts must have exactly 2 values");
        return [payouts[0], payouts[1]];
    }
}