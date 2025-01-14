// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFMRealityAdapter.sol";

import "test/unit/dummy/RealityETH.sol";

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
    DummyRealityETH public realityEth;

    address USER = address(1);
    address DUMMY_ARBITRATOR = address(0x42424242);

    uint256 public constant INITIAL_SUPPLY = 1000000 ether;
    uint256 public constant USER_SUPPLY = 5000 ether;
    uint256 public constant INITIAL_LIQUIDITY = 1000 ether;
    uint32 public constant QUESTION_TIMEOUT = 86400;
    uint256 public constant MIN_BOND = 100;

    function setUp() public virtual {
        vm.label(USER, "User");
        vm.label(DUMMY_ARBITRATOR, "Arbitrator");

        conditionalTokens = new ConditionalTokens();
        vm.label(address(conditionalTokens), "ConditionalTokens");
        wrapped1155Factory = new Wrapped1155Factory();
        vm.label(address(wrapped1155Factory), "Wrapped1155Factory");
        realityEth = new DummyRealityETH();
        vm.label(address(realityEth), "RealityETH");
    }
}

contract DependenciesTest is Base {
    function testDependenciesDeployments() public view {
        assertTrue(address(conditionalTokens) != address(0));
        assertTrue(address(wrapped1155Factory) != address(0));
        assertTrue(address(realityEth) != address(0));
    }
}

contract DeployCoreContractsBase is Base {
    FlatCFMOracleAdapter public oracleAdapter;
    FlatCFMFactory public factory;

    function setUp() public virtual override {
        super.setUp();
        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(realityEth)), DUMMY_ARBITRATOR, QUESTION_TIMEOUT, MIN_BOND);
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
    CollateralToken public collateralToken;
    FlatCFM cfm;
    ConditionalScalarMarket conditionalMarketA;
    ConditionalScalarMarket conditionalMarketB;
    ConditionalScalarMarket conditionalMarketC;
    bytes32 cfmConditionId;

    function _recordConditionIdAndScalarMarkets() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 found = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics[0] == keccak256("FlatCFMCreated(address,bytes32)")
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

        vm.recordLogs();
        cfm = factory.createFlatCFM(
            oracleAdapter,
            1,
            2,
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

        vm.startPrank(USER);

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(METRIC_SPLIT_AMOUNT_A);
        conditionalMarketB.split(METRIC_SPLIT_AMOUNT_B);

        vm.stopPrank();

        (,,,,,, wrappedShortA, wrappedLongA, wrappedInvalidA) = conditionalMarketA.wrappedCTData();
        (,,,,,, wrappedShortB, wrappedLongB, wrappedInvalidB) = conditionalMarketB.wrappedCTData();
        (,,,,,, wrappedShortC, wrappedLongC, wrappedInvalidC) = conditionalMarketC.wrappedCTData();
    }
}

contract SplitTest is SplitTestBase {
    function testSplitPositionA() public view {
        assertEq(wrappedShortA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(wrappedInvalidA.balanceOf(USER), DECISION_SPLIT_AMOUNT);
        assertEq(userBalanceOutcomeA(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_A);
    }

    function testSplitPositionB() public view {
        assertEq(wrappedShortB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedLongB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(wrappedInvalidB.balanceOf(USER), DECISION_SPLIT_AMOUNT / 2);
        assertEq(userBalanceOutcomeB(), DECISION_SPLIT_AMOUNT - METRIC_SPLIT_AMOUNT_B);
    }

    function testSplitPositionC() public view {
        assertEq(wrappedShortC.balanceOf(USER), 0);
        assertEq(wrappedLongC.balanceOf(USER), 0);
        assertEq(wrappedInvalidC.balanceOf(USER), 0);
        assertEq(userBalanceOutcomeC(), DECISION_SPLIT_AMOUNT);
    }

    function userBalanceOutcomeA() private view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketA.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function userBalanceOutcomeB() private view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketB.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
    }

    function userBalanceOutcomeC() private view returns (uint256) {
        (,, bytes32 parentCollectionId,) = conditionalMarketC.ctParams();
        return conditionalTokens.balanceOf(USER, conditionalTokens.getPositionId(collateralToken, parentCollectionId));
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

        collateralToken.approve(address(conditionalTokens), CONTRACT_LIQUIDITY);
        conditionalTokens.splitPosition(
            collateralToken, bytes32(0), cfmConditionId, _decisionDiscreetPartition(), CONTRACT_LIQUIDITY
        );

        conditionalTokens.setApprovalForAll(address(conditionalMarketA), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketB), true);
        conditionalTokens.setApprovalForAll(address(conditionalMarketC), true);

        conditionalMarketA.split(CONTRACT_LIQUIDITY);
        conditionalMarketB.split(CONTRACT_LIQUIDITY);
        conditionalMarketC.split(CONTRACT_LIQUIDITY);

        //(,,,,,, IERC20 shortA, IERC20 longA,) = conditionalMarketA.wrappedCTData();
        ammA = new SimpleAMM(wrappedShortA, wrappedLongA);
        vm.label(address(ammA), "amm A");
        //(,,,,,, IERC20 shortB, IERC20 longB,) = conditionalMarketB.wrappedCTData();
        ammB = new SimpleAMM(wrappedShortB, wrappedLongB);
        vm.label(address(ammB), "amm B");
        // (,,,,,, IERC20 shortC, IERC20 longC,) = conditionalMarketC.wrappedCTData();
        ammC = new SimpleAMM(wrappedShortC, wrappedLongC);
        vm.label(address(ammC), "amm C");

        wrappedShortA.approve(address(ammA), CONTRACT_LIQUIDITY);
        wrappedLongA.approve(address(ammA), CONTRACT_LIQUIDITY);
        ammA.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortB.approve(address(ammB), CONTRACT_LIQUIDITY);
        wrappedLongB.approve(address(ammB), CONTRACT_LIQUIDITY);
        ammB.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        wrappedShortC.approve(address(ammC), CONTRACT_LIQUIDITY);
        wrappedLongC.approve(address(ammC), CONTRACT_LIQUIDITY);
        ammC.addLiquidity(CONTRACT_LIQUIDITY, CONTRACT_LIQUIDITY);

        vm.startPrank(USER);

        wrappedShortA.approve(address(ammA), TRADE_AMOUNT);
        ammA.swap(true, TRADE_AMOUNT);

        wrappedShortB.approve(address(ammB), TRADE_AMOUNT);
        ammB.swap(true, TRADE_AMOUNT);

        conditionalMarketC.split(METRIC_SPLIT_AMOUNT_C);
        wrappedShortC.approve(address(ammC), TRADE_AMOUNT * 2);
        ammC.swap(true, TRADE_AMOUNT * 2);

        vm.stopPrank();
    }

    function marketBalanceA(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketA.wrappedCTData();
        return short ? wrappedShortA.balanceOf(address(ammA)) : wrappedLongA.balanceOf(address(ammA));
    }

    function marketBalanceB(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketB.wrappedCTData();
        return short ? wrappedShortB.balanceOf(address(ammB)) : wrappedLongB.balanceOf(address(ammB));
    }

    function marketBalanceC(bool short) internal view returns (uint256) {
        //(,,,,,, IERC20 _short, IERC20 _long,) = conditionalMarketC.wrappedCTData();
        return short ? wrappedShortC.balanceOf(address(ammC)) : wrappedLongC.balanceOf(address(ammC));
    }
}

contract TradeTest is TradeTestBase {
    function testTradeOutcomeA() public view {
        //(,,,,,, IERC20 sA, IERC20 lA,) = conditionalMarketA.wrappedCTData();
        assertTrue(wrappedShortA.balanceOf(USER) < DECISION_SPLIT_AMOUNT);
        assertTrue(wrappedLongA.balanceOf(USER) > DECISION_SPLIT_AMOUNT);
        assertTrue(marketBalanceA(true) > CONTRACT_LIQUIDITY);
        assertTrue(marketBalanceA(false) < CONTRACT_LIQUIDITY);
    }

    function testTradeOutcomeB() public view {
        //(,,,,,, IERC20 sA, IERC20 lA,) = conditionalMarketA.wrappedCTData();
        //(,,,,,, IERC20 sB, IERC20 lB,) = conditionalMarketB.wrappedCTData();
        assertEq(
            DECISION_SPLIT_AMOUNT / 2 - wrappedShortB.balanceOf(USER),
            DECISION_SPLIT_AMOUNT - wrappedShortA.balanceOf(USER)
        );
        assertEq(
            wrappedLongB.balanceOf(USER) - (DECISION_SPLIT_AMOUNT / 2),
            wrappedLongA.balanceOf(USER) - DECISION_SPLIT_AMOUNT
        );
        assertEq(marketBalanceA(true), marketBalanceB(true));
        assertEq(marketBalanceA(false), marketBalanceB(false));
    }

    function testTradeOutcomeC() public view {
        //(,,,,,, IERC20 sB, IERC20 lB,) = conditionalMarketB.wrappedCTData();
        //(,,,,,, IERC20 sC, IERC20 lC,) = conditionalMarketC.wrappedCTData();
        assertTrue(wrappedShortC.balanceOf(USER) < wrappedShortB.balanceOf(USER));
        assertTrue(wrappedLongC.balanceOf(USER) > wrappedLongB.balanceOf(USER));
        assertTrue(marketBalanceC(true) > marketBalanceB(true));
        assertTrue(marketBalanceC(false) < marketBalanceB(false));
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

        wrappedLongA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedShortA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedInvalidA.approve(address(conditionalMarketA), MERGE_AMOUNT);
        wrappedLongB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedShortB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedInvalidB.approve(address(conditionalMarketB), MERGE_AMOUNT);
        wrappedLongC.approve(address(conditionalMarketC), mergeMax);
        wrappedShortC.approve(address(conditionalMarketC), mergeMax);
        wrappedInvalidC.approve(address(conditionalMarketC), mergeMax);

        conditionalMarketA.merge(MERGE_AMOUNT);
        conditionalMarketB.merge(MERGE_AMOUNT);
        conditionalMarketC.merge(mergeMax);

        vm.stopPrank();
    }
}

contract MergeTest is MergeTestBase {
    function testMergePositionsA() public view {
        assertEq(wrappedShortA.balanceOf(USER), userBalanceBeforeMerge.AShort - MERGE_AMOUNT);
        assertEq(wrappedLongA.balanceOf(USER), userBalanceBeforeMerge.ALong - MERGE_AMOUNT);
    }

    function testMergePositionsB() public view {
        assertEq(wrappedShortB.balanceOf(USER), userBalanceBeforeMerge.BShort - MERGE_AMOUNT);
        assertEq(wrappedLongB.balanceOf(USER), userBalanceBeforeMerge.BLong - MERGE_AMOUNT);
    }

    function testMergePositionsC() public view {
        // Merged everything back into collateral
        assertEq(wrappedShortC.balanceOf(USER), 0);
    }
}

//contract ResolveDecisionTest is MergeTest {}
//
//contract TradeAfterDecisionTest is ResolveDecisionTest {}
//
//contract ResolveConditionalsTest is TradeAfterDecisionTest {}
//
//contract RedeemTest is ResolveConditionalsTest {}
