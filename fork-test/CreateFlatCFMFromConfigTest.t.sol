// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import "src/Types.sol";

contract CreateFlatCFMFromConfigTest is Test {
    string constant CONFIG_FILE_PATH = "fork-test/flatcfm-50-outcomes.json";

    function setUp() public {
        // Optionally set up any local mocks, but here we just read the real config.
    }

    function testCreateGas() public {
        string memory jsonContent = vm.readFile(CONFIG_FILE_PATH);

        FlatCFMFactory factory = FlatCFMFactory(_parseFactoryAddress(jsonContent));
        uint256 decisionTemplateId = _parseDecisionTemplateId(jsonContent);
        uint256 metricTemplateId = _parseMetricTemplateId(jsonContent);
        FlatCFMQuestionParams memory flatQParams = _parseFlatCFMQuestionParams(jsonContent);
        GenericScalarQuestionParams memory scalarQParams = _parseGenericScalarQuestionParams(jsonContent);
        address collateralAddr = _parseCollateralAddress(jsonContent);

        vm.startSnapshotGas("createFlatCFM");
        FlatCFM market =
            factory.create(decisionTemplateId, metricTemplateId, flatQParams, scalarQParams, IERC20(collateralAddr));
        uint256 gasUsed = vm.stopSnapshotGas();

        uint256 maxGasAllowed = 30_000_000;
        assertLt(gasUsed, maxGasAllowed, "Gas usage too high, above 30M");

        console.log("FlatCFM deployed at:", address(market));
        console.log("Gas used for create:", gasUsed);
    }

    /// -----------------------------------------
    /// JSON & parsing helpers (same as the script)
    /// -----------------------------------------
    function _parseFactoryAddress(string memory json) private pure returns (address) {
        return vm.parseJsonAddress(json, ".factoryAddress");
    }

    function _parseDecisionTemplateId(string memory json) private pure returns (uint256) {
        return vm.parseJsonUint(json, ".decisionTemplateId");
    }

    function _parseMetricTemplateId(string memory json) private pure returns (uint256) {
        return vm.parseJsonUint(json, ".metricTemplateId");
    }

    function _parseFlatCFMQuestionParams(string memory json) private pure returns (FlatCFMQuestionParams memory) {
        string memory roundName = vm.parseJsonString(json, ".roundName");
        bytes memory outcomeNamesRaw = vm.parseJson(json, ".outcomeNames");
        string[] memory outcomeNames = abi.decode(outcomeNamesRaw, (string[]));
        uint256 openingTimeDecision = vm.parseJsonUint(json, ".openingTimeDecision");
        require(openingTimeDecision <= type(uint32).max, "openingTime overflow");

        return FlatCFMQuestionParams({
            roundName: roundName,
            outcomeNames: outcomeNames,
            openingTime: uint32(openingTimeDecision)
        });
    }

    function _parseGenericScalarQuestionParams(string memory json)
        private
        pure
        returns (GenericScalarQuestionParams memory)
    {
        string memory metricName = vm.parseJsonString(json, ".metricName");
        string memory startDate = vm.parseJsonString(json, ".startDate");
        string memory endDate = vm.parseJsonString(json, ".endDate");
        uint256 minValue = vm.parseJsonUint(json, ".minValue");
        uint256 maxValue = vm.parseJsonUint(json, ".maxValue");
        uint256 openingTimeMetric = vm.parseJsonUint(json, ".openingTimeMetric");
        require(openingTimeMetric <= type(uint32).max, "openingTime overflow");

        return GenericScalarQuestionParams({
            metricName: metricName,
            startDate: startDate,
            endDate: endDate,
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: uint32(openingTimeMetric)
        });
    }

    function _parseCollateralAddress(string memory json) private pure returns (address) {
        return vm.parseJsonAddress(json, ".collateralToken");
    }
}
