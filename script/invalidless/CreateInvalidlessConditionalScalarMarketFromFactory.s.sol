// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "src/invalidless/InvalidlessConditionalScalarMarketFactory.sol";
import "src/FlatCFMOracleAdapter.sol";
import {ScalarParams, ConditionalScalarCTParams, GenericScalarQuestionParams} from "src/Types.sol";
import "../ConditionalScalarMarketJsonParser.s.sol";

contract CreateInvalidlessConditionalScalarMarketFromFactory is Script, ConditionalScalarMarketJsonParser {
    struct Config {
        address factoryAddress;
        address oracleAdapterAddress;
        uint256 templateId;
        string outcomeName;
        uint256 minValue;
        uint256 maxValue;
        uint32 openingTime;
        uint256[2] defaultInvalidPayouts;
        address collateralToken;
    }

    function run() external {
        vm.startBroadcast();

        Config memory config = parseConfig();

        // Use the factory to deploy the market
        InvalidlessConditionalScalarMarketFactory factory = InvalidlessConditionalScalarMarketFactory(config.factoryAddress);

        InvalidlessConditionalScalarMarket icsm = factory.createInvalidlessConditionalScalarMarket(
            FlatCFMOracleAdapter(config.oracleAdapterAddress),
            config.templateId,
            config.outcomeName,
            GenericScalarQuestionParams({
                scalarParams: ScalarParams({
                    minValue: config.minValue,
                    maxValue: config.maxValue
                }),
                openingTime: config.openingTime
            }),
            config.defaultInvalidPayouts,
            IERC20(config.collateralToken)
        );

        console.log("Deployed InvalidlessConditionalScalarMarket via factory at:", address(icsm));
        
        // Access struct fields directly
        (bytes32 questionId, bytes32 conditionId,,) = icsm.ctParams();
        console.log("Question ID:", vm.toString(questionId));
        console.log("Condition ID:", vm.toString(conditionId));

        vm.stopBroadcast();
    }

    function parseConfig() public view returns (Config memory) {
        string memory configPath = _getJsonFilePath();
        string memory json = vm.readFile(configPath);

        return Config({
            factoryAddress: vm.parseJsonAddress(json, ".factoryAddress"),
            oracleAdapterAddress: _parseOracleAdapterAddress(json),
            templateId: _parseTemplateId(json),
            outcomeName: _parseOutcomeName(json),
            minValue: _parseMinValue(json),
            maxValue: _parseMaxValue(json),
            openingTime: _parseOpeningTime(json),
            defaultInvalidPayouts: _parseDefaultInvalidPayouts(json),
            collateralToken: _parseCollateralAddress(json)
        });
    }
}
