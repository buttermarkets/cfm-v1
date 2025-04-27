// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol";
import {Arbitrator} from "@realityeth/packages/contracts/flat/Arbitrator-development.sol";

import "../vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";

import "src/invalidless/InvalidlessFlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";
import {CollateralToken, Base} from "./Scenario.t.sol";

contract DeployCoreContractsBase is Base {
    FlatCFMOracleAdapter public oracleAdapter;
    InvalidlessFlatCFMFactory public factory;

    function setUp() public virtual override {
        super.setUp();

        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(arbitrator), QUESTION_TIMEOUT, MIN_BOND);
        factory = new InvalidlessFlatCFMFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );
    }
}

contract CreateDecisionMarketBase is DeployCoreContractsBase {
    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams genericScalarQuestionParams;
    CollateralToken public collateralToken;
    uint256 decisionTemplateId;
    uint256 metricTemplateId;
    FlatCFM cfm;
    InvalidlessConditionalScalarMarket conditionalMarketA;
    InvalidlessConditionalScalarMarket conditionalMarketB;
    InvalidlessConditionalScalarMarket conditionalMarketC;
    bytes32 cfmConditionId;
    FlatCFM cfm2;
    InvalidlessConditionalScalarMarket conditionalMarketA2;
    InvalidlessConditionalScalarMarket conditionalMarketB2;
    InvalidlessConditionalScalarMarket conditionalMarketC2;
    bytes32 cfmConditionId2;

    uint256[2] defaultInvalidPayouts = [uint256(1), uint256(3)];

    function setUp() public virtual override {
        super.setUp();

        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");

        collateralToken.transfer(USER, USER_SUPPLY);

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Project A";
        outcomes[1] = "Project B";
        outcomes[2] = "Project C";

        decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomes, openingTime: uint32(block.timestamp + 2 days)});
        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 10000}),
            openingTime: uint32(block.timestamp + 90 days)
        });

        decisionTemplateId = reality.createTemplate(
            '{"title": "Which project will get funded?", "type": "uint", "category": "test", "lang": "en"}'
        );
        metricTemplateId = reality.createTemplate(
            // solhint-disable-next-line
            '{"title": "Between 2025-02-15 and 2025-06-15, what is the awesomeness in thousand USD, for %s on Coolchain?", "type": "uint", "category": "cfm-metric", "lang": "en"}'
        );

        vm.recordLogs();
        cfm = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm, defaultInvalidPayouts);
        }
        _recordConditionIdAndScalarMarkets();

        vm.label(address(cfm), "DecisionMarket");
        vm.label(address(conditionalMarketA), "ConditionalMarketA");
        vm.label(address(conditionalMarketB), "ConditionalMarketB");
        vm.label(address(conditionalMarketC), "ConditionalMarketC");

        vm.recordLogs();
        cfm2 = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm2, defaultInvalidPayouts);
        }
        _recordConditionIdAndScalarMarkets2();

        vm.label(address(cfm2), "DecisionMarket2");
        vm.label(address(conditionalMarketA2), "ConditionalMarketA2");
        vm.label(address(conditionalMarketB2), "ConditionalMarketB2");
        vm.label(address(conditionalMarketC2), "ConditionalMarketC2");
    }

    function _recordConditionIdAndScalarMarkets() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == keccak256("FlatCFMCreated(address,bytes32,address)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)
            ) {
                cfmConditionId = abi.decode(logs[i].data, (bytes32));
            }
            if (
                logs[i].topics[0] == keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)
            ) {
                address csmAddr = address(uint160(uint256(logs[i].topics[2])));
                if (found == 0) {
                    conditionalMarketA = InvalidlessConditionalScalarMarket(csmAddr);
                } else if (found == 1) {
                    conditionalMarketB = InvalidlessConditionalScalarMarket(csmAddr);
                } else if (found == 2) {
                    conditionalMarketC = InvalidlessConditionalScalarMarket(csmAddr);
                }
                found++;
            }
        }

        assertEq(found, 3, "wrong number of CSMs");
    }

    function _recordConditionIdAndScalarMarkets2() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == keccak256("FlatCFMCreated(address,bytes32,address)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm2)
            ) {
                cfmConditionId2 = abi.decode(logs[i].data, (bytes32));
            }
            if (
                logs[i].topics[0] == keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm2)
            ) {
                address csmAddr = address(uint160(uint256(logs[i].topics[2])));
                if (found == 0) {
                    conditionalMarketA2 = InvalidlessConditionalScalarMarket(csmAddr);
                } else if (found == 1) {
                    conditionalMarketB2 = InvalidlessConditionalScalarMarket(csmAddr);
                } else if (found == 2) {
                    conditionalMarketC2 = InvalidlessConditionalScalarMarket(csmAddr);
                }
                found++;
            }
        }

        assertEq(found, 3, "wrong number of CSMs");
    }

    function _decisionDiscreetPartition() public view returns (uint256[] memory) {
        // +1 for Invalid
        uint256[] memory partition = new uint256[](cfm.outcomeCount() + 1);
        for (uint256 i = 0; i < cfm.outcomeCount() + 1; i++) {
            partition[i] = 1 << i;
        }
        return partition;
    }
}

contract CreateDecisionMarketTest is CreateDecisionMarketBase {
    function testSameQuestion() public view {
        assertEq(cfm.questionId(), cfm2.questionId());
    }

    function testDifferentCondition() public view {
        assertNotEq(cfmConditionId, cfmConditionId2);
    }
}
