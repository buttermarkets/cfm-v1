// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "src/invalidless/InvalidlessConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import "src/libs/String31.sol";
import {ScalarParams, ConditionalScalarCTParams, GenericScalarQuestionParams} from "src/Types.sol";
import {InvalidlessWrappedConditionalTokensData} from "src/invalidless/Types.sol";
import "./ConditionalScalarMarketJsonParser.s.sol";

contract DeployInvalidlessConditionalScalarMarket is Script, ConditionalScalarMarketJsonParser {
    using Clones for address;
    using String31 for string;

    struct Config {
        uint256 templateId;
        uint256 minValue;
        uint256 maxValue;
        address conditionalTokens;
        address wrapped1155Factory;
        uint32 openingTime;
        uint256[2] defaultInvalidPayouts;
    }

    function run() external {
        vm.startBroadcast();

        Config memory config = parseConfig();

        // Deploy the InvalidlessConditionalScalarMarket
        InvalidlessConditionalScalarMarket icsm = deployMarket(config);

        console.log("Deployed InvalidlessConditionalScalarMarket at:", address(icsm));
        console.log("Question ID:", vm.toString(icsm.ctParams().questionId));
        console.log("Condition ID:", vm.toString(icsm.ctParams().conditionId));

        vm.stopBroadcast();
    }

    function parseConfig() public view returns (Config memory) {
        string memory configPath = _getJsonFilePath();
        string memory json = vm.readFile(configPath);

        // Parse default invalid payouts array
        bytes memory payoutsRaw = vm.parseJson(json, ".defaultInvalidPayouts");
        uint256[] memory payouts = abi.decode(payoutsRaw, (uint256[]));
        require(payouts.length == 2, "defaultInvalidPayouts must have exactly 2 values");

        return Config({
            templateId: _parseTemplateId(json),
            outcomeName: _parseOutcomeName(json),
            minValue: _parseMinValue(json),
            maxValue: _parseMaxValue(json),
            openingTime: _parseOpeningTime(json),
            defaultInvalidPayouts: _parseDefaultInvalidPayouts(json),
            conditionalTokens: _parseConditionalTokensAddress(json),
            wrapped1155Factory: _parseWrapped1155FactoryAddress(json)
        });
    }

    function deployMarket(Config memory config) public returns (InvalidlessConditionalScalarMarket) {
        // Validate config
        require(
            config.defaultInvalidPayouts[0] > 0 || config.defaultInvalidPayouts[1] > 0,
            "Invalid payouts cannot both be zero"
        );
        require(config.maxValue > config.minValue, "maxValue must be greater than minValue");
        // Deploy and clone the implementation
        address implementation = address(new InvalidlessConditionalScalarMarket());
        InvalidlessConditionalScalarMarket icsm = InvalidlessConditionalScalarMarket(implementation.clone());

        string memory json = vm.readFile(_getJsonFilePath());

        FlatCFMOracleAdapter oracleAdapter = FlatCFMOracleAdapter(_parseOracleAdapterAddress(json));
        IConditionalTokens conditionalTokens = IConditionalTokens(config.conditionalTokens);
        IWrapped1155Factory wrapped1155Factory = IWrapped1155Factory(config.wrapped1155Factory);
        IERC20 collateralToken = IERC20(_parseCollateralAddress(json));

        // Ask the metric question
        GenericScalarQuestionParams memory scalarParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: config.minValue, maxValue: config.maxValue}),
            openingTime: config.openingTime
        });

        bytes32 questionId =
            oracleAdapter.askMetricQuestion{value: msg.value}(config.templateId, scalarParams, config.outcomeName);

        // Prepare condition (2 outcomes: Short, Long)
        bytes32 conditionId = conditionalTokens.getConditionId(address(icsm), questionId, 2);
        if (conditionalTokens.getOutcomeSlotCount(conditionId) == 0) {
            conditionalTokens.prepareCondition(address(icsm), questionId, 2);
        }

        // Deploy wrapped conditional tokens
        InvalidlessWrappedConditionalTokensData memory wrappedCTData =
            deployWrappedTokens(config.outcomeName, collateralToken, conditionalTokens, wrapped1155Factory, conditionId);

        // Initialize the market
        ConditionalScalarCTParams memory ctParams = ConditionalScalarCTParams({
            questionId: questionId,
            conditionId: conditionId,
            parentCollectionId: bytes32(0), // No parent collection for standalone market
            collateralToken: collateralToken
        });

        icsm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            ctParams,
            ScalarParams({minValue: config.minValue, maxValue: config.maxValue}),
            wrappedCTData,
            config.defaultInvalidPayouts
        );

        return icsm;
    }

    function deployWrappedTokens(
        string memory outcomeName,
        IERC20 collateralToken,
        IConditionalTokens conditionalTokens,
        IWrapped1155Factory wrapped1155Factory,
        bytes32 conditionId
    ) internal returns (InvalidlessWrappedConditionalTokensData memory) {
        uint8 decimals = IERC20Metadata(address(collateralToken)).decimals();

        // Create token names and symbols
        bytes memory shortData = abi.encodePacked(
            string.concat(outcomeName, "-Short").toString31(), string.concat(outcomeName, "-ST").toString31(), decimals
        );
        bytes memory longData = abi.encodePacked(
            string.concat(outcomeName, "-Long").toString31(), string.concat(outcomeName, "-LG").toString31(), decimals
        );

        // Get position IDs
        uint256 shortPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, 1)
        );
        uint256 longPosId = conditionalTokens.getPositionId(
            collateralToken, conditionalTokens.getCollectionId(bytes32(0), conditionId, 2)
        );

        // Deploy wrapped tokens
        IERC20 wrappedShort = wrapped1155Factory.requireWrapped1155(conditionalTokens, shortPosId, shortData);
        IERC20 wrappedLong = wrapped1155Factory.requireWrapped1155(conditionalTokens, longPosId, longData);

        return InvalidlessWrappedConditionalTokensData({
            shortData: shortData,
            longData: longData,
            shortPositionId: shortPosId,
            longPositionId: longPosId,
            wrappedShort: wrappedShort,
            wrappedLong: wrappedLong
        });
    }
}
