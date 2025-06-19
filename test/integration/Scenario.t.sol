// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable no-console
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol";
import {Arbitrator} from "@realityeth/packages/contracts/flat/Arbitrator-development.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";

import "./vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "./vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "./fake/SimpleAMM.sol";

contract CollateralToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Collateral Token", "CLT") {
        _mint(msg.sender, initialSupply);
    }
}

contract Base is Test {
    ConditionalTokens public conditionalTokens;
    Wrapped1155Factory public wrapped1155Factory;
    RealityETH_v3_0 public reality;
    Arbitrator public arbitrator;
    CollateralToken public collateralToken;

    address USER = makeAddr("USER");

    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant USER_SUPPLY = 5000 ether;
    uint256 public constant INITIAL_LIQUIDITY = 1000 ether;
    uint32 public constant QUESTION_TIMEOUT = 86_400;
    uint256 public constant MIN_BOND = 100;

    function setUp() public virtual {
        vm.label(USER, "User");

        conditionalTokens = new ConditionalTokens();
        vm.label(address(conditionalTokens), "ConditionalTokens");
        wrapped1155Factory = new Wrapped1155Factory();
        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
        reality = new RealityETH_v3_0();
        vm.label(address(reality), "RealityETH");
        arbitrator = new Arbitrator();
        arbitrator.setRealitio(address(reality));
        vm.label(address(arbitrator), "Arbitrator");

        collateralToken = new CollateralToken(INITIAL_SUPPLY);
        vm.label(address(collateralToken), "$COL");
        collateralToken.transfer(USER, USER_SUPPLY);
    }

    function _getDiscreetPartition() internal pure returns (uint256[] memory) {
        uint256[] memory partition = new uint256[](3);
        partition[0] = 1; // short
        partition[1] = 2; // long
        partition[2] = 4; // invalid
        return partition;
    }
}

contract DependenciesTest is Base {
    function testDependenciesDeployments() public view {
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(reality) != address(0));
    }
}

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

contract DeployCoreContractsTest is DeployCoreContractsBase {
    function testDecisionMarketFactoryDeployment() public view {
        assertTrue(address(factory) != address(0));
    }

    function testOracleAdapterDeployment() public view {
        assertTrue(address(oracleAdapter) != address(0));
    }
}

contract CreateDecisionMarketBase is DeployCoreContractsBase {
    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams genericScalarQuestionParams;
    uint256 decisionTemplateId;
    uint256 metricTemplateId;
    FlatCFM cfm;
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;
    bytes32 cfmConditionId;

    function setUp() public virtual override {
        super.setUp();

        string[] memory outcomes = new string[](3);
        outcomes[0] = "Project A";
        outcomes[1] = "Project B";
        outcomes[2] = "Project C";

        decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomes, openingTime: uint32(block.timestamp + 2 days)});
        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 10_000}),
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
    function testDecisionMarketCreated() public view {
        assertTrue(address(cfm) != address(0));
    }

    function testCfmConditionIdSet() public view {
        assertTrue(cfmConditionId != bytes32(0), "conditionId not found");
    }

    function testOutcomeCount() public view {
        assertEq(cfm.outcomeCount(), 3);
    }
}

contract CreateConditionalMarketsTest is CreateDecisionMarketBase {
    function testConditionalScalarMarketsCreated() public view {
        assertTrue(address(conditionalMarketA) != address(0), "Conditional market A not found");
        assertTrue(address(conditionalMarketB) != address(0), "Conditional market B not found");
        assertTrue(address(conditionalMarketC) != address(0), "Conditional market C not found");
    }

    function testParentCollectionIdA() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 0),
            "parent collection ID mismatch A"
        );
    }

    function testParentCollectionIdB() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 1),
            "parent collection ID mismatch B"
        );
    }

    function testParentCollectionIdC() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 2),
            "parent collection ID mismatch C"
        );
    }
}

contract SplitPositionTestBase is CreateDecisionMarketBase {
    uint256 constant DECISION_SPLIT_AMOUNT = USER_SUPPLY / 10;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(USER);
        collateralToken.approve(address(conditionalTokens), DECISION_SPLIT_AMOUNT);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition(), DECISION_SPLIT_AMOUNT
        );
        vm.stopPrank();
    }
}

contract SplitPositionTest is SplitPositionTestBase {
    function testSplitPositionABalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 0),
            "parent collection ID mismatch A"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch"
        );
    }

    function testSplitPositionBBalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 1),
            "parent collection ID mismatch B"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch B"
        );
    }

    function testSplitPositionCBalance() public view {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        assertEq(
            parentCollectionId,
            conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 2),
            "parent collection ID mismatch C"
        );
        assertEq(
            conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId)),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch C"
        );
    }

    function testSplitPositionInvalidBalance() public view {
        assertEq(
            conditionalTokens.balanceOf(
                USER,
                conditionalTokens.getPositionId(
                    collateralToken, conditionalTokens.getCollectionId(0, cfmConditionId, 1 << 3)
                )
            ),
            DECISION_SPLIT_AMOUNT,
            "Decision split amount mismatch Invalid"
        );
    }
}

contract SplitTestBase is SplitPositionTestBase {
    uint256 constant METRIC_SPLIT_AMOUNT_A = DECISION_SPLIT_AMOUNT;
    uint256 constant METRIC_SPLIT_AMOUNT_B = DECISION_SPLIT_AMOUNT / 2;

    IERC20 wrappedShortA;
    IERC20 wrappedLongA;
    IERC20 wrappedInvalidA;
    IERC20 wrappedShortB;
    IERC20 wrappedLongB;
    IERC20 wrappedInvalidB;
    IERC20 wrappedShortC;
    IERC20 wrappedLongC;
    IERC20 wrappedInvalidC;

    function setUp() public virtual override {
        super.setUp();
        (, bytes32 conditionIdA, bytes32 parentCollectionIdA,) = conditionalMarketA.ctParams();
        (
            bytes memory shortDataA,
            bytes memory longDataA,
            bytes memory invalidDataA,
            uint256 shortPositionIdA,
            uint256 longPositionIdA,
            uint256 invalidPositionIdA,
            ,
            ,
        ) = conditionalMarketA.wrappedCTData();

        (, bytes32 conditionIdB, bytes32 parentCollectionIdB,) = conditionalMarketB.ctParams();
        (
            bytes memory shortDataB,
            bytes memory longDataB,
            bytes memory invalidDataB,
            uint256 shortPositionIdB,
            uint256 longPositionIdB,
            uint256 invalidPositionIdB,
            ,
            ,
        ) = conditionalMarketB.wrappedCTData();

        vm.startPrank(USER);

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        // 1. First, split position (have the contract create the outcome tokens)
        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdA, conditionIdA, _getDiscreetPartition(), METRIC_SPLIT_AMOUNT_A
        );

        // 2. Transfer each position directly to the wrapper factory which will handle wrapping
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), shortPositionIdA, METRIC_SPLIT_AMOUNT_A, shortDataA
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), longPositionIdA, METRIC_SPLIT_AMOUNT_A, longDataA
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), invalidPositionIdA, METRIC_SPLIT_AMOUNT_A, invalidDataA
        );

        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdB, conditionIdB, _getDiscreetPartition(), METRIC_SPLIT_AMOUNT_B
        );

        // 2. Transfer each position directly to the wrapper factory which will handle wrapping
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), shortPositionIdB, METRIC_SPLIT_AMOUNT_B, shortDataB
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), longPositionIdB, METRIC_SPLIT_AMOUNT_B, longDataB
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), invalidPositionIdB, METRIC_SPLIT_AMOUNT_B, invalidDataB
        );
        vm.stopPrank();

        (,,,,,, wrappedShortA, wrappedLongA, wrappedInvalidA) = conditionalMarketA.wrappedCTData();
        (,,,,,, wrappedShortB, wrappedLongB, wrappedInvalidB) = conditionalMarketB.wrappedCTData();
        (,,,,,, wrappedShortC, wrappedLongC, wrappedInvalidC) = conditionalMarketC.wrappedCTData();
    }

    function _userBalanceOutcomeA() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function _userBalanceOutcomeB() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function _userBalanceOutcomeC() internal view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }
}

contract SplitTest is SplitTestBase {
    function testSplitPositionA() public view {
        assertEq(wrappedShortA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedInvalidA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        // METRIC_SPLIT_AMOUNT_A is used since we've simulated splitting with direct minting
        assertEq(_userBalanceOutcomeA(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_A);
        console.log("Tested split position A");
    }

    function testSplitPositionB() public view {
        assertEq(wrappedShortB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedLongB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedInvalidB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(_userBalanceOutcomeB(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_B);
        console.log("Tested split position B");
    }

    function testSplitPositionC() public view {
        assertEq(wrappedShortC.balanceOf(USER), 0);
        assertEq(wrappedInvalidC.balanceOf(USER), 0);
        assertEq(_userBalanceOutcomeC(), DECISION_SPLIT_AMOUNT);
        console.log("Tested split position C");
    }
}

contract TradeTestBase is SplitTestBase, ERC1155Holder {
    uint256 constant TRADE_AMOUNT = USER_SUPPLY / 40;
    uint256 constant CONTRACT_LIQUIDITY = INITIAL_SUPPLY / 100;
    SimpleAMM public ammA;
    SimpleAMM public ammB;
    SimpleAMM public ammC;
    uint256 constant METRIC_SPLIT_AMOUNT_C = DECISION_SPLIT_AMOUNT / 2;

    function setUp() public virtual override {
        super.setUp();

        // Get contract's initial positions
        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        // Extract all the required data from market A
        (, bytes32 conditionIdA, bytes32 parentCollectionIdA,) = conditionalMarketA.ctParams();
        (
            bytes memory shortDataA,
            bytes memory longDataA,
            bytes memory invalidDataA,
            uint256 shortPositionIdA,
            uint256 longPositionIdA,
            uint256 invalidPositionIdA,
            IERC20 wrappedShortA,
            IERC20 wrappedLongA,
            IERC20 wrappedInvalidA
        ) = conditionalMarketA.wrappedCTData();

        // Extract data from market B
        (, bytes32 conditionIdB, bytes32 parentCollectionIdB,) = conditionalMarketB.ctParams();
        (
            bytes memory shortDataB,
            bytes memory longDataB,
            bytes memory invalidDataB,
            uint256 shortPositionIdB,
            uint256 longPositionIdB,
            uint256 invalidPositionIdB,
            IERC20 wrappedShortB,
            IERC20 wrappedLongB,
            IERC20 wrappedInvalidB
        ) = conditionalMarketB.wrappedCTData();

        // Extract data from market C
        (, bytes32 conditionIdC, bytes32 parentCollectionIdC,) = conditionalMarketC.ctParams();
        (
            bytes memory shortDataC,
            bytes memory longDataC,
            bytes memory invalidDataC,
            uint256 shortPositionIdC,
            uint256 longPositionIdC,
            uint256 invalidPositionIdC,
            IERC20 wrappedShortC,
            IERC20 wrappedLongC,
            IERC20 wrappedInvalidC
        ) = conditionalMarketC.wrappedCTData();

        // Direct split and wrap for market A
        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdA, conditionIdA, _getDiscreetPartition(), CONTRACT_LIQUIDITY
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), shortPositionIdA, CONTRACT_LIQUIDITY, shortDataA
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), longPositionIdA, CONTRACT_LIQUIDITY, longDataA
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), invalidPositionIdA, CONTRACT_LIQUIDITY, invalidDataA
        );

        // Direct split and wrap for market B
        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdB, conditionIdB, _getDiscreetPartition(), CONTRACT_LIQUIDITY
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), shortPositionIdB, CONTRACT_LIQUIDITY, shortDataB
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), longPositionIdB, CONTRACT_LIQUIDITY, longDataB
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), invalidPositionIdB, CONTRACT_LIQUIDITY, invalidDataB
        );

        // Direct split and wrap for market C
        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdC, conditionIdC, _getDiscreetPartition(), CONTRACT_LIQUIDITY
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), shortPositionIdC, CONTRACT_LIQUIDITY, shortDataC
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), longPositionIdC, CONTRACT_LIQUIDITY, longDataC
        );
        conditionalTokens.safeTransferFrom(
            address(this), address(wrapped1155Factory), invalidPositionIdC, CONTRACT_LIQUIDITY, invalidDataC
        );

        // Create AMMs with the wrapped tokens
        ammA = new SimpleAMM(wrappedShortA, wrappedLongA);
        vm.label(address(ammA), "amm A");
        ammB = new SimpleAMM(wrappedShortB, wrappedLongB);
        vm.label(address(ammB), "amm B");
        ammC = new SimpleAMM(wrappedShortC, wrappedLongC);
        vm.label(address(ammC), "amm C");

        // Add liquidity to AMMs
        wrappedShortA.approve(address(ammA), CONTRACT_LIQUIDITY);
        wrappedLongA.approve(address(ammA), CONTRACT_LIQUIDITY);
        ammA.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortB.approve(address(ammB), CONTRACT_LIQUIDITY);
        wrappedLongB.approve(address(ammB), CONTRACT_LIQUIDITY);
        ammB.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortC.approve(address(ammC), CONTRACT_LIQUIDITY);
        wrappedLongC.approve(address(ammC), CONTRACT_LIQUIDITY);
        ammC.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        // Now user trades
        vm.startPrank(USER);

        // Trade on AMM A
        wrappedShortA.approve(address(ammA), TRADE_AMOUNT);
        ammA.swap(true, TRADE_AMOUNT);

        // Trade on AMM B
        wrappedShortB.approve(address(ammB), TRADE_AMOUNT);
        ammB.swap(true, TRADE_AMOUNT);

        // For market C, user needs to first split and wrap tokens then trade
        // Direct split and wrap for user with market C
        conditionalTokens.splitPosition(
            collateralToken, parentCollectionIdC, conditionIdC, _getDiscreetPartition(), METRIC_SPLIT_AMOUNT_C
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), shortPositionIdC, METRIC_SPLIT_AMOUNT_C, shortDataC
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), longPositionIdC, METRIC_SPLIT_AMOUNT_C, longDataC
        );
        conditionalTokens.safeTransferFrom(
            USER, address(wrapped1155Factory), invalidPositionIdC, METRIC_SPLIT_AMOUNT_C, invalidDataC
        );

        // Then trade on AMM C
        wrappedShortC.approve(address(ammC), TRADE_AMOUNT * 2);
        ammC.swap(true, TRADE_AMOUNT * 2);

        vm.stopPrank();
    }

    function _marketBalanceA(bool short) internal view returns (uint256) {
        return short ? wrappedShortA.balanceOf(address(ammA)) : wrappedLongA.balanceOf(address(ammA));
    }

    function _marketBalanceB(bool short) internal view returns (uint256) {
        return short ? wrappedShortB.balanceOf(address(ammB)) : wrappedLongB.balanceOf(address(ammB));
    }

    function _marketBalanceC(bool short) internal view returns (uint256) {
        return short ? wrappedShortC.balanceOf(address(ammC)) : wrappedLongC.balanceOf(address(ammC));
    }
}

contract TradeTest is TradeTestBase {
    function testTradeOutcomeA() public view {
        assertTrue(wrappedShortA.balanceOf(USER) < DECISION_SPLIT_AMOUNT);
        assertTrue(wrappedLongA.balanceOf(USER) > DECISION_SPLIT_AMOUNT);
        assertTrue(_marketBalanceA(true) > CONTRACT_LIQUIDITY);
        assertTrue(_marketBalanceA(false) < CONTRACT_LIQUIDITY);
        console.log("Tested trade outcome A");
    }

    function testTradeOutcomeB() public view {
        assertEq(
            DECISION_SPLIT_AMOUNT / 2 - wrappedShortB.balanceOf(USER),
            DECISION_SPLIT_AMOUNT - wrappedShortA.balanceOf(USER)
        );
        assertEq(
            wrappedLongB.balanceOf(USER) - (DECISION_SPLIT_AMOUNT / 2),
            wrappedLongA.balanceOf(USER) - DECISION_SPLIT_AMOUNT
        );
        assertEq(_marketBalanceA(true), _marketBalanceB(true));
        assertEq(_marketBalanceA(false), _marketBalanceB(false));
        console.log("Tested trade outcome B");
    }

    function testTradeOutcomeC() public view {
        assertTrue(wrappedShortC.balanceOf(USER) < wrappedShortB.balanceOf(USER));
        assertTrue(wrappedLongC.balanceOf(USER) > wrappedLongB.balanceOf(USER));
        assertTrue(_marketBalanceC(true) > _marketBalanceB(true));
        assertTrue(_marketBalanceC(false) < _marketBalanceB(false));
        console.log("Tested trade outcome C");
    }
}

contract MergeTestBase is TradeTestBase {
    uint256 constant MERGE_AMOUNT = DECISION_SPLIT_AMOUNT / 10;

    struct UserBalance {
        uint256 AShort;
        uint256 ALong;
        uint256 AInvalid;
        uint256 BShort;
        uint256 BLong;
        uint256 BInvalid;
        uint256 CShort;
        uint256 CLong;
        uint256 CInvalid;
    }

    UserBalance userBalanceBeforeMerge;

    function setUp() public virtual override {
        super.setUp();

        uint256 someTradeAmount = wrappedLongC.balanceOf(USER) / 4;

        vm.startPrank(USER);
        wrappedLongC.approve(address(ammC), someTradeAmount);
        ammC.swap(false, someTradeAmount);
        uint256 mergeMax = wrappedShortC.balanceOf(USER);

        userBalanceBeforeMerge = UserBalance({
            AShort: wrappedShortA.balanceOf(USER),
            ALong: wrappedLongA.balanceOf(USER),
            AInvalid: wrappedInvalidA.balanceOf(USER),
            BShort: wrappedShortB.balanceOf(USER),
            BLong: wrappedLongB.balanceOf(USER),
            BInvalid: wrappedInvalidB.balanceOf(USER),
            CShort: wrappedShortC.balanceOf(USER),
            CLong: wrappedLongC.balanceOf(USER),
            CInvalid: wrappedInvalidC.balanceOf(USER)
        });

        // For market A
        (, bytes32 conditionIdA, bytes32 parentCollectionIdA,) = conditionalMarketA.ctParams();
        (
            bytes memory shortDataA,
            bytes memory longDataA,
            bytes memory invalidDataA,
            uint256 shortPositionIdA,
            uint256 longPositionIdA,
            uint256 invalidPositionIdA,
            IERC20 wrappedShortA,
            IERC20 wrappedLongA,
            IERC20 wrappedInvalidA
        ) = conditionalMarketA.wrappedCTData();

        // 1. Unwrap tokens first (send wrapped tokens and get ERC1155 back)
        wrappedShortA.approve(address(wrapped1155Factory), MERGE_AMOUNT);
        wrappedLongA.approve(address(wrapped1155Factory), MERGE_AMOUNT);
        wrappedInvalidA.approve(address(wrapped1155Factory), MERGE_AMOUNT);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdA, MERGE_AMOUNT, USER, shortDataA);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdA, MERGE_AMOUNT, USER, longDataA);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdA, MERGE_AMOUNT, USER, invalidDataA);

        // 2. Merge positions (using the received ERC1155 tokens)
        conditionalTokens.mergePositions(
            collateralToken, parentCollectionIdA, conditionIdA, _getDiscreetPartition(), MERGE_AMOUNT
        );

        // For market B
        (, bytes32 conditionIdB, bytes32 parentCollectionIdB,) = conditionalMarketB.ctParams();
        (
            bytes memory shortDataB,
            bytes memory longDataB,
            bytes memory invalidDataB,
            uint256 shortPositionIdB,
            uint256 longPositionIdB,
            uint256 invalidPositionIdB,
            IERC20 wrappedShortB,
            IERC20 wrappedLongB,
            IERC20 wrappedInvalidB
        ) = conditionalMarketB.wrappedCTData();

        // 1. Unwrap tokens
        wrappedShortB.approve(address(wrapped1155Factory), MERGE_AMOUNT);
        wrappedLongB.approve(address(wrapped1155Factory), MERGE_AMOUNT);
        wrappedInvalidB.approve(address(wrapped1155Factory), MERGE_AMOUNT);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdB, MERGE_AMOUNT, USER, shortDataB);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdB, MERGE_AMOUNT, USER, longDataB);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdB, MERGE_AMOUNT, USER, invalidDataB);

        // 2. Merge positions
        conditionalTokens.mergePositions(
            collateralToken, parentCollectionIdB, conditionIdB, _getDiscreetPartition(), MERGE_AMOUNT
        );

        // For market C
        (, bytes32 conditionIdC, bytes32 parentCollectionIdC,) = conditionalMarketC.ctParams();
        (
            bytes memory shortDataC,
            bytes memory longDataC,
            bytes memory invalidDataC,
            uint256 shortPositionIdC,
            uint256 longPositionIdC,
            uint256 invalidPositionIdC,
            IERC20 wrappedShortC,
            IERC20 wrappedLongC,
            IERC20 wrappedInvalidC
        ) = conditionalMarketC.wrappedCTData();

        uint256 longBalanceC = wrappedLongC.balanceOf(USER);
        uint256 invalidBalanceC = wrappedInvalidC.balanceOf(USER);
        if (longBalanceC < mergeMax) mergeMax = longBalanceC;
        if (invalidBalanceC < mergeMax) mergeMax = invalidBalanceC;

        // 1. Unwrap tokens
        wrappedShortC.approve(address(wrapped1155Factory), mergeMax);
        wrappedLongC.approve(address(wrapped1155Factory), mergeMax);
        wrappedInvalidC.approve(address(wrapped1155Factory), mergeMax);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdC, mergeMax, USER, shortDataC);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdC, mergeMax, USER, longDataC);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdC, mergeMax, USER, invalidDataC);

        // 2. Merge positions
        conditionalTokens.mergePositions(
            collateralToken, parentCollectionIdC, conditionIdC, _getDiscreetPartition(), mergeMax
        );

        vm.stopPrank();
    }
}

contract MergeTest is MergeTestBase {
    function testMergePositionsA() public view {
        console.log("Testing merge positions A");
        assertEq(wrappedShortA.balanceOf(USER), userBalanceBeforeMerge.AShort - MERGE_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), userBalanceBeforeMerge.ALong - MERGE_AMOUNT);
        assertEq(wrappedInvalidA.balanceOf(USER), userBalanceBeforeMerge.AInvalid - MERGE_AMOUNT);
    }

    function testMergePositionsB() public view {
        console.log("Testing merge positions B");
        assertEq(wrappedShortB.balanceOf(USER), userBalanceBeforeMerge.BShort - MERGE_AMOUNT);
        assertEq(wrappedLongB.balanceOf(USER), userBalanceBeforeMerge.BLong - MERGE_AMOUNT);
        assertEq(wrappedInvalidB.balanceOf(USER), userBalanceBeforeMerge.BInvalid - MERGE_AMOUNT);
    }

    function testMergePositionsC() public view {
        console.log("Testing merge positions C");
        // Since we merge the minimum available amount, check that balances decreased appropriately
        uint256 shortBalanceC = wrappedShortC.balanceOf(USER);
        uint256 longBalanceC = wrappedLongC.balanceOf(USER);
        uint256 invalidBalanceC = wrappedInvalidC.balanceOf(USER);

        uint256 expectedMergeAmount = userBalanceBeforeMerge.CShort;
        if (userBalanceBeforeMerge.CLong < expectedMergeAmount) expectedMergeAmount = userBalanceBeforeMerge.CLong;
        if (userBalanceBeforeMerge.CInvalid < expectedMergeAmount) {
            expectedMergeAmount = userBalanceBeforeMerge.CInvalid;
        }

        assertEq(shortBalanceC, userBalanceBeforeMerge.CShort - expectedMergeAmount);
        assertEq(longBalanceC, userBalanceBeforeMerge.CLong - expectedMergeAmount);
        assertEq(invalidBalanceC, userBalanceBeforeMerge.CInvalid - expectedMergeAmount);
    }
}

contract FormatAdapter is FlatCFMRealityAdapter {
    constructor() FlatCFMRealityAdapter(IRealityETH(address(0)), address(0), 0, 0) {}

    function formatDecisionQuestionParams(FlatCFMQuestionParams memory flatCFMQuestionParams)
        external
        pure
        returns (string memory)
    {
        return _formatDecisionQuestionParams(flatCFMQuestionParams);
    }

    function formatMetricQuestionParams(string memory outcomeName) external pure returns (string memory) {
        return _formatMetricQuestionParams(outcomeName);
    }
}

contract BadAnswerSubmitDecisionAnswerTest is MergeTestBase {
    address ANSWERER = makeAddr("answerer");

    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
    }

    function testCantResolveIfUnresolved() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question was settled too soon and has not been reopened");
        cfm.resolve();
    }

    function testCantResolveIfUnresolvedReopened() public {
        FormatAdapter formatAdapter = new FormatAdapter();

        vm.startPrank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(block.timestamp + QUESTION_TIMEOUT + 1);
        bytes32 newQuestionId = reality.reopenQuestion(
            decisionTemplateId,
            formatAdapter.formatDecisionQuestionParams(decisionQuestionParams),
            address(arbitrator),
            QUESTION_TIMEOUT,
            decisionQuestionParams.openingTime,
            0,
            MIN_BOND,
            cfm.questionId()
        );
        deal(ANSWERER, MIN_BOND);
        reality.submitAnswer{value: MIN_BOND}(
            newQuestionId, 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.stopPrank();

        vm.warp(block.timestamp + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question replacement was settled too soon and has not been reopened");
        cfm.resolve();
    }

    function testCanResolveIfInvalid() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            cfm.questionId(), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0
        );

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 1);
    }

    function testCanResolveIfLargerValue() public {
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(cfm.questionId(), bytes32(uint256(1 << cfm.outcomeCount() + 1)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 1);
    }
}

contract GoodAnswerSubmitDecisionAnswerTestBase is MergeTestBase {
    address ANSWERER = makeAddr("answerer");

    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(cfm.questionId(), /*0b101*/ bytes32(uint256(5)), 0);
    }
}

contract GoodAnswerSubmitDecisionAnswerTest is GoodAnswerSubmitDecisionAnswerTestBase {
    address CHALLENGER = makeAddr("challenger");

    function testCantResolveBeforeTimeout() public {
        vm.expectRevert("question must be finalized");
        cfm.resolve();
    }

    function testCantResolveAfterTimeoutIfChallenged() public {
        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND);

        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(cfm.questionId(), bytes32(uint256(1)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("question must be finalized");
        cfm.resolve();
    }

    function testCanResolveAfterChallengeTimeout() public {
        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND);
        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(cfm.questionId(), bytes32(uint256(3)), 0);

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT - 1 + QUESTION_TIMEOUT);
        cfm.resolve();

        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), (i == 0 || i == 1) ? 1 : 0);
        }
        assertEq(conditionalTokens.payoutNumerators(cfmConditionId, cfm.outcomeCount()), 0);
    }
}

contract GoodAnswerCfmResolveTestBase is GoodAnswerSubmitDecisionAnswerTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(decisionQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        cfm.resolve();
    }
}

contract GoodAnswerCfmResolveTest is GoodAnswerCfmResolveTestBase {
    function testReportedPayouts() public view {
        for (uint256 i = 0; i < cfm.outcomeCount(); i++) {
            assertEq(conditionalTokens.payoutNumerators(cfmConditionId, i), (i == 0 || i == 2) ? 1 : 0);
        }
    }
}

contract DecisionOutcomeRedeemTestBase is GoodAnswerCfmResolveTestBase {
    uint256 prevDeciRedeemBalanceA;
    uint256 prevDeciRedeemBalanceB;
    uint256 prevDeciRedeemBalanceC;
    uint256 prevDeciRedeemBalanceCollat;

    function setUp() public virtual override {
        super.setUp();

        prevDeciRedeemBalanceA = _userBalanceOutcomeA();
        prevDeciRedeemBalanceB = _userBalanceOutcomeB();
        prevDeciRedeemBalanceC = _userBalanceOutcomeC();
        prevDeciRedeemBalanceCollat = collateralToken.balanceOf(USER);

        vm.startPrank(USER);
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition());
        vm.stopPrank();
    }
}

contract DecisionOutcomeRedeemTest is DecisionOutcomeRedeemTestBase {
    function testRedeemUpdatesCollateralBalanceWithWinners() public view {
        uint256 expectedDeciRedeemCollatPayout = (prevDeciRedeemBalanceA + prevDeciRedeemBalanceC) / 2;
        assertEq(collateralToken.balanceOf(USER), prevDeciRedeemBalanceCollat + expectedDeciRedeemCollatPayout);
    }
}

contract BadAnswerSubmitMetricAsnwerTest is DecisionOutcomeRedeemTestBase {
    bytes32 csmAQuestionId;
    bytes32 csmAConditionId;

    function setUp() public virtual override {
        super.setUp();
        console.log("BadAnswerSubmitMetricAsnwerTest: Setting up");

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND);

        (csmAQuestionId, csmAConditionId,,) = conditionalMarketA.ctParams();
        console.log("BadAnswerSubmitMetricAsnwerTest: Setup complete");
    }

    function testCantResolveIfUnresolved() public {
        console.log("Testing can't resolve if unresolved");
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("Question was settled too soon and has not been reopened");
        conditionalMarketA.resolve();
    }

    function testCanResolveIfInvalid() public {
        console.log("Testing can resolve if invalid");
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 1);
    }

    function testCanResolveIfTooHigh() public {
        console.log("Testing can resolve if too high");
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(
            csmAQuestionId, bytes32(uint256(genericScalarQuestionParams.scalarParams.maxValue + 1)), 0
        );

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }

    function testCanResolveIfTooLow() public {
        console.log("Testing can resolve if too low");
        vm.prank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(csmAQuestionId, bytes32(uint256(0)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }
}

contract GoodAnswerSubmitMetricAnswerTestBase is DecisionOutcomeRedeemTestBase {
    bytes32 csmAQuestionId;
    bytes32 csmAConditionId;
    bytes32 csmAParentCollectionid;
    bytes32 csmBQuestionId;
    bytes32 csmBConditionId;
    bytes32 csmBParentCollectionid;
    bytes32 csmCQuestionId;
    bytes32 csmCConditionId;
    bytes32 csmCParentCollectionid;

    function setUp() public virtual override {
        super.setUp();
        console.log("GoodAnswerSubmitMetricAnswerTestBase: Setting up");

        vm.warp(genericScalarQuestionParams.openingTime + 1);
        deal(ANSWERER, MIN_BOND * 3);
        (csmAQuestionId, csmAConditionId, csmAParentCollectionid,) = conditionalMarketA.ctParams();
        (csmBQuestionId, csmBConditionId, csmBParentCollectionid,) = conditionalMarketB.ctParams();
        (csmCQuestionId, csmCConditionId, csmCParentCollectionid,) = conditionalMarketC.ctParams();
        vm.startPrank(ANSWERER);
        reality.submitAnswer{value: MIN_BOND}(csmAQuestionId, bytes32(uint256(5000)), 0);
        reality.submitAnswer{value: MIN_BOND}(csmBQuestionId, bytes32(uint256(2500)), 0);
        reality.submitAnswer{value: MIN_BOND}(csmCQuestionId, bytes32(uint256(10_000)), 0);
        vm.stopPrank();
    }
}

contract GoodAnswerSubmitMetricAnswerTest is GoodAnswerSubmitMetricAnswerTestBase {
    address constant CHALLENGER = address(0x1111);

    function testCantResolveBeforeTimeout() public {
        vm.expectRevert("question must be finalized");
        conditionalMarketA.resolve();
    }

    function testCantResolveAfterTimeoutIfChallenged() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);

        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(csmAQuestionId, bytes32(uint256(1)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        vm.expectRevert("question must be finalized");
        conditionalMarketA.resolve();
    }

    function testCanResolveAfterChallengeTimeout() public {
        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1);
        deal(CHALLENGER, MIN_BOND * 2);
        vm.prank(CHALLENGER);
        reality.submitAnswer{value: 2 * MIN_BOND}(csmAQuestionId, bytes32(uint256(0)), 0);

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT - 1 + QUESTION_TIMEOUT);
        conditionalMarketA.resolve();

        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 1);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 0);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }
}

contract GoodAnswerCsmResolveTestBase is GoodAnswerSubmitMetricAnswerTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(genericScalarQuestionParams.openingTime + QUESTION_TIMEOUT + 1);
        conditionalMarketA.resolve();
        conditionalMarketB.resolve();
        conditionalMarketC.resolve();
    }
}

contract GoodAnswerCsmResolveTest is GoodAnswerCsmResolveTestBase {
    function testReportedPayoutsA() public view {
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 0), 5000);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 1), 5000);
        assertEq(conditionalTokens.payoutNumerators(csmAConditionId, 2), 0);
    }

    function testReportedPayoutsB() public view {
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 0), 7500);
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 1), 2500);
        assertEq(conditionalTokens.payoutNumerators(csmBConditionId, 2), 0);
    }

    function testReportedPayoutsC() public view {
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 0), 0);
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 1), 1);
        assertEq(conditionalTokens.payoutNumerators(csmCConditionId, 2), 0);
    }
}

contract CsmRedeemTestBase is GoodAnswerCsmResolveTestBase {
    uint256 prevCondRedeemBalanceA;
    uint256 prevCondRedeemBalanceAShort;
    uint256 prevCondRedeemBalanceALong;
    uint256 prevCondRedeemBalanceAInvalid;
    uint256 prevCondRedeemBalanceB;
    uint256 prevCondRedeemBalanceBShort;
    uint256 prevCondRedeemBalanceBLong;
    uint256 prevCondRedeemBalanceBInvalid;
    uint256 prevCondRedeemBalanceC;
    uint256 prevCondRedeemBalanceCShort;
    uint256 prevCondRedeemBalanceCLong;
    uint256 prevCondRedeemBalanceCInvalid;

    function setUp() public virtual override {
        super.setUp();

        prevCondRedeemBalanceA = _userBalanceOutcomeA();
        prevCondRedeemBalanceAShort = wrappedShortA.balanceOf(USER);
        prevCondRedeemBalanceALong = wrappedLongA.balanceOf(USER);
        prevCondRedeemBalanceAInvalid = wrappedInvalidA.balanceOf(USER);
        prevCondRedeemBalanceB = _userBalanceOutcomeB();
        prevCondRedeemBalanceBShort = wrappedShortB.balanceOf(USER);
        prevCondRedeemBalanceBLong = wrappedLongB.balanceOf(USER);
        prevCondRedeemBalanceBInvalid = wrappedInvalidB.balanceOf(USER);
        prevCondRedeemBalanceC = _userBalanceOutcomeC();
        prevCondRedeemBalanceCShort = wrappedShortC.balanceOf(USER);
        prevCondRedeemBalanceCLong = wrappedLongC.balanceOf(USER);
        prevCondRedeemBalanceCInvalid = wrappedInvalidC.balanceOf(USER);

        vm.startPrank(USER);

        // For Market A
        uint256 shortAmountA = prevCondRedeemBalanceAShort;
        uint256 longAmountA = prevCondRedeemBalanceALong;
        uint256 invalidAmountA = prevCondRedeemBalanceAInvalid;

        // 1. Get position data
        (, bytes32 conditionIdA, bytes32 parentCollectionIdA,) = conditionalMarketA.ctParams();
        (
            bytes memory shortDataA,
            bytes memory longDataA,
            bytes memory invalidDataA,
            uint256 shortPositionIdA,
            uint256 longPositionIdA,
            uint256 invalidPositionIdA,
            ,
            ,
        ) = conditionalMarketA.wrappedCTData();

        // 2. Approve tokens for unwrapping
        wrappedShortA.approve(address(wrapped1155Factory), shortAmountA);
        wrappedLongA.approve(address(wrapped1155Factory), longAmountA);
        wrappedInvalidA.approve(address(wrapped1155Factory), invalidAmountA);

        // 3. Unwrap tokens
        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdA, shortAmountA, USER, shortDataA);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdA, longAmountA, USER, longDataA);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdA, invalidAmountA, USER, invalidDataA);

        // 4. Redeem positions
        conditionalTokens.redeemPositions(collateralToken, parentCollectionIdA, conditionIdA, _getDiscreetPartition());

        // For Market B - same pattern
        uint256 shortAmountB = prevCondRedeemBalanceBShort;
        uint256 longAmountB = prevCondRedeemBalanceBLong;
        uint256 invalidAmountB = prevCondRedeemBalanceBInvalid;

        (, bytes32 conditionIdB, bytes32 parentCollectionIdB,) = conditionalMarketB.ctParams();
        (
            bytes memory shortDataB,
            bytes memory longDataB,
            bytes memory invalidDataB,
            uint256 shortPositionIdB,
            uint256 longPositionIdB,
            uint256 invalidPositionIdB,
            ,
            ,
        ) = conditionalMarketB.wrappedCTData();

        wrappedShortB.approve(address(wrapped1155Factory), shortAmountB);
        wrappedLongB.approve(address(wrapped1155Factory), longAmountB);
        wrappedInvalidB.approve(address(wrapped1155Factory), invalidAmountB);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdB, shortAmountB, USER, shortDataB);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdB, longAmountB, USER, longDataB);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdB, invalidAmountB, USER, invalidDataB);

        conditionalTokens.redeemPositions(collateralToken, parentCollectionIdB, conditionIdB, _getDiscreetPartition());

        // For Market C - redeem half
        uint256 shortAmountC = prevCondRedeemBalanceCShort / 2;
        uint256 longAmountC = prevCondRedeemBalanceCLong / 2;
        uint256 invalidAmountC = prevCondRedeemBalanceCInvalid / 2;

        (, bytes32 conditionIdC, bytes32 parentCollectionIdC,) = conditionalMarketC.ctParams();
        (
            bytes memory shortDataC,
            bytes memory longDataC,
            bytes memory invalidDataC,
            uint256 shortPositionIdC,
            uint256 longPositionIdC,
            uint256 invalidPositionIdC,
            ,
            ,
        ) = conditionalMarketC.wrappedCTData();

        wrappedShortC.approve(address(wrapped1155Factory), shortAmountC);
        wrappedLongC.approve(address(wrapped1155Factory), longAmountC);
        wrappedInvalidC.approve(address(wrapped1155Factory), invalidAmountC);

        wrapped1155Factory.unwrap(conditionalTokens, shortPositionIdC, shortAmountC, USER, shortDataC);
        wrapped1155Factory.unwrap(conditionalTokens, longPositionIdC, longAmountC, USER, longDataC);
        wrapped1155Factory.unwrap(conditionalTokens, invalidPositionIdC, invalidAmountC, USER, invalidDataC);

        conditionalTokens.redeemPositions(collateralToken, parentCollectionIdC, conditionIdC, _getDiscreetPartition());

        vm.stopPrank();
    }
}

contract CsmRedeemTest is CsmRedeemTestBase {
    function testRedeemUpdatesOutcomeABalance() public view {
        console.log("Testing redeem updates outcome A balance");
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        uint256 positionId = conditionalTokens.getPositionId(collateralToken, parentCollectionId);

        uint256 expectedBalance =
            prevCondRedeemBalanceA + (prevCondRedeemBalanceAShort + prevCondRedeemBalanceALong) / 2;
        assertEq(conditionalTokens.balanceOf(USER, positionId), expectedBalance);
    }

    function testRedeemUpdatesOutcomeBBalance() public view {
        console.log("Testing redeem updates outcome B balance");
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        uint256 positionId = conditionalTokens.getPositionId(collateralToken, parentCollectionId);

        uint256 expectedPayout =
            (prevCondRedeemBalanceBShort * 7500 + prevCondRedeemBalanceBLong * 2500) / 10_000;
        uint256 expectedBalance = prevCondRedeemBalanceB + expectedPayout;
        assertEq(conditionalTokens.balanceOf(USER, positionId), expectedBalance);
    }

    function testRedeemUpdatesOutcomeCBalance() public view {
        console.log("Testing redeem updates outcome C balance");
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        uint256 positionId = conditionalTokens.getPositionId(collateralToken, parentCollectionId);

        // Calculate the actual redeemed amount based on what was unwrapped
        uint256 actualRedeemedAmount = prevCondRedeemBalanceCLong / 2;
        uint256 expectedBalance = prevCondRedeemBalanceC + actualRedeemedAmount;

        assertEq(conditionalTokens.balanceOf(USER, positionId), expectedBalance);

        // Check that remaining tokens are still there
        assertEq(wrappedLongC.balanceOf(USER), prevCondRedeemBalanceCLong - actualRedeemedAmount);
        assertEq(wrappedInvalidC.balanceOf(USER), prevCondRedeemBalanceCInvalid - (prevCondRedeemBalanceCInvalid / 2));
    }
}

contract RedeemBackToCollateralTest is CsmRedeemTestBase {
    uint256 prevFinalRedeemCollateralBalance;

    function setUp() public virtual override {
        super.setUp();
        console.log("RedeemBackToCollateralTest: Setting up");

        prevFinalRedeemCollateralBalance = collateralToken.balanceOf(USER);

        vm.startPrank(USER);
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition());
        vm.stopPrank();

        console.log("RedeemBackToCollateralTest: Setup complete");
    }

    function testCollateral() public view {
        console.log("Testing final collateral redemption");
        uint256 payoutA = (prevCondRedeemBalanceAShort * 5000 + prevCondRedeemBalanceALong * 5000) / 10_000;
        uint256 payoutC = prevCondRedeemBalanceCLong / 2;

        // Decision market resolution: A and C are winners, payout is 0.5 each
        uint256 collateralA = payoutA / 2;
        uint256 collateralC = payoutC / 2;

        uint256 expectedPayout = collateralA + collateralC;
        assertEq(collateralToken.balanceOf(USER), prevFinalRedeemCollateralBalance + expectedPayout);
    }
}
