// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";

import "script/invalidless/CreateFlatCFMFromConfig.s.sol";

import "src/invalidless/InvalidlessFlatCFMFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import "src/Types.sol";

contract CreateInvalidlessFlatCFMFromConfigTest is Test {
    string constant CONFIG_FILE_PATH = "test/fork/flatcfm-50-outcomes-invalidless.json";
    CreateInvalidlessFlatCFMFromConfig script;

    function setUp() public {
        script = new CreateInvalidlessFlatCFMFromConfig();
    }

    function testCreateGas() public {
        string memory jsonContent = vm.readFile(CONFIG_FILE_PATH);

        InvalidlessFlatCFMFactory factory = InvalidlessFlatCFMFactory(script._parseFactoryAddress(jsonContent));
        FlatCFMOracleAdapter oracleAdapter = FlatCFMOracleAdapter(script._parseOracleAdapterAddress(jsonContent));
        uint256 decisionTemplateId = script._parseDecisionTemplateId(jsonContent);
        uint256 metricTemplateId = script._parseMetricTemplateId(jsonContent);
        FlatCFMQuestionParams memory flatQParams = script._parseFlatCFMQuestionParams(jsonContent);
        GenericScalarQuestionParams memory scalarQParams = script._parseGenericScalarQuestionParams(jsonContent);
        uint256[2] memory defaultInvalidPayouts = script._parseDefaultInvalidPayouts(jsonContent);
        address collateralAddr = script._parseCollateralAddress(jsonContent);
        string memory metadataUri = script._parseMetadataUri(jsonContent);

        vm.startSnapshotGas("createFlatCFM");
        FlatCFM market = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            flatQParams,
            scalarQParams,
            defaultInvalidPayouts,
            IERC20(collateralAddr),
            metadataUri
        );
        uint256 gasUsed = vm.stopSnapshotGas();

        uint256 maxGasAllowed = 30_000_000;
        assertLt(gasUsed, maxGasAllowed, "Gas usage too high, above 30M");

        console.log("FlatCFM deployed at:", address(market));
        console.log("Gas used for create:", gasUsed);

        // Create all conditional scalar markets
        for (uint256 i = 0; i < flatQParams.outcomeNames.length; i++) {
            InvalidlessConditionalScalarMarket icsm = factory.createConditionalScalarMarket(market);
            console.log("InvalidlessConditionalScalarMarket deployed at:", address(icsm));
        }
    }
}
