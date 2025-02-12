// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol";
import {Arbitrator} from "@realityeth/packages/contracts/flat/Arbitrator-development.sol";

import "./vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";
import {CollateralToken, Base} from "./Scenario.t.sol";

contract DeployCoreContractsBase is Base {
    FlatCFMOracleAdapter public oracleAdapter;
    FlatCFMFactory public factory;

    function setUp() public virtual override {
        super.setUp();

        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(arbitrator), QUESTION_TIMEOUT, MIN_BOND);
        factory = new FlatCFMFactory(
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
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;
    bytes32 cfmConditionId;

    function setUp() public virtual override {
        super.setUp();

        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");

        collateralToken.transfer(USER, USER_SUPPLY);

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Same";
        outcomes[1] = "Same";
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
            factory.createConditionalScalarMarket(cfm);
        }
        _recordConditionIdAndScalarMarkets();

        vm.label(address(cfm), "DecisionMarket");
        vm.label(address(conditionalMarketA), "ConditionalMarketA");
        vm.label(address(conditionalMarketB), "ConditionalMarketB");
        vm.label(address(conditionalMarketC), "ConditionalMarketC");
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
                logs[i].topics[0] == keccak256("ConditionalScalarMarketCreated(address,address,uint256)")
                    && address(uint160(uint256(logs[i].topics[1]))) == address(cfm)
            ) {
                address csmAddr = address(uint160(uint256(logs[i].topics[2])));
                if (found == 0) {
                    conditionalMarketA = ConditionalScalarMarket(csmAddr);
                } else if (found == 1) {
                    conditionalMarketB = ConditionalScalarMarket(csmAddr);
                } else if (found == 2) {
                    conditionalMarketC = ConditionalScalarMarket(csmAddr);
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
    function testQuestionId() public view {
        (bytes32 csmAQuestionId,,,) = conditionalMarketA.ctParams();
        (bytes32 csmBQuestionId,,,) = conditionalMarketB.ctParams();
        assertEq(csmAQuestionId, csmBQuestionId);
    }

    function testConditionId() public view {
        (, bytes32 csmAConditionId,,) = conditionalMarketA.ctParams();
        (, bytes32 csmBConditionId,,) = conditionalMarketB.ctParams();
        assertNotEq(csmAConditionId, csmBConditionId);
    }
}
