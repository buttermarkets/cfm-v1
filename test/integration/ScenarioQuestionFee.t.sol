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

// TODO arbitrator sets question fee via `setQuestionFee`

contract DeployCoreContractsBase is Base {
    FlatCFMOracleAdapter public oracleAdapter;
    FlatCFMFactory public factory;

    uint256 constant QUESTION_FEE = 0.2 ether;

    function setUp() public virtual override {
        super.setUp();

        vm.prank(address(arbitrator));
        reality.setQuestionFee(QUESTION_FEE);

        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(arbitrator), QUESTION_TIMEOUT, MIN_BOND);
        factory = new FlatCFMFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );
    }
}

contract CreateDecisionMarketOtherTest is DeployCoreContractsBase {
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
    }

    function testCFMNeedFee() public {
        vm.expectRevert("ETH provided must cover question fee");
        cfm = factory.createFlatCFM(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );
    }

    function testCSMNeedFee() public {
        deal(address(this), QUESTION_FEE);
        cfm = factory.createFlatCFM{value: QUESTION_FEE}(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );

        vm.expectRevert("ETH provided must cover question fee");
        factory.createConditionalScalarMarket(cfm);
    }

    function testCFMExtraFeeIsBounty() public {
        deal(address(this), QUESTION_FEE + 1);
        cfm = factory.createFlatCFM{value: QUESTION_FEE + 1}(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );

        assertEq(reality.balanceOf(address(arbitrator)), QUESTION_FEE);

        (,,,,,, uint256 bounty,,,,) = reality.questions(cfm.questionId());
        assertEq(bounty, 1);
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

        deal(address(this), QUESTION_FEE * 4);

        vm.recordLogs();
        cfm = factory.createFlatCFM{value: QUESTION_FEE}(
            oracleAdapter,
            decisionTemplateId,
            metricTemplateId,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            "ipfs://hello world"
        );
        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket{value: QUESTION_FEE}(cfm);
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
    function testDecisionMarketCreated() public view {
        assertTrue(address(cfm) != address(0));
    }

    function testCfmConditionIdSet() public view {
        assertTrue(cfmConditionId != bytes32(0), "conditionId not found");
    }

    function testOutcomeCount() public view {
        assertEq(cfm.outcomeCount(), 3);
    }

    function testArbitratorGotPaid() public view {
        assertEq(reality.balanceOf(address(arbitrator)), QUESTION_FEE * 4);
    }
}
