// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import "./FlatCFMJsonParser.s.sol";

contract CreateFlatCFMFromConfig is Script, FlatCFMJsonParser {
    function run() external {
        vm.startBroadcast();

        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        FlatCFMFactory factory = FlatCFMFactory(_parseFactoryAddress(jsonContent));
        FlatCFMOracleAdapter oracleAdapter = FlatCFMOracleAdapter(_parseOracleAdapterAddress(jsonContent));
        uint256 decisionTemplateId = _parseDecisionTemplateId(jsonContent);
        uint256 metricTemplateId = _parseMetricTemplateId(jsonContent);
        FlatCFMQuestionParams memory decisionQuestionParams = _parseFlatCFMQuestionParams(jsonContent);
        GenericScalarQuestionParams memory genericScalarQuestionParams = _parseGenericScalarQuestionParams(jsonContent);
        address collateralAddr = _parseCollateralAddress(jsonContent);
        string memory metadataUri = _parseMetadataUri(jsonContent);

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
            ConditionalScalarMarket csm = factory.createConditionalScalarMarket(cfm);
            console.log("Deployed ConditionalScalarMarket at:", address(csm));
        }

        vm.stopBroadcast();
    }
}