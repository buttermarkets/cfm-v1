// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/utils/Strings.sol";

import "src/FlatCFM.sol";
import "src/FlatCFMRealityAdapter.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/libs/String31.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/invalidless/InvalidlessFlatCFMFactory.sol";
import "src/invalidless/InvalidlessConditionalScalarMarket.sol";

import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyRealityETH} from "./dummy/RealityETH.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract Base is Test {
    InvalidlessFlatCFMFactory public factory;
    // This could be a dummy.
    FlatCFMRealityAdapter public oracleAdapter;
    DummyConditionalTokens public conditionalTokens;
    DummyRealityETH public reality;
    IWrapped1155Factory public wrapped1155Factory;
    IERC20 public collateralToken;

    uint32 constant QUESTION_TIMEOUT = 1000;
    uint256 constant MIN_BOND = 1_000_000_000_000;

    function setUp() public virtual {
        conditionalTokens = new DummyConditionalTokens();
        reality = new DummyRealityETH();
        wrapped1155Factory = new DummyWrapped1155Factory();
        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(0x00), QUESTION_TIMEOUT, MIN_BOND);
        collateralToken = new TestERC20();

        factory = new InvalidlessFlatCFMFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );

        vm.label(address(factory), "factory");
        vm.label(address(oracleAdapter), "reality adapter");
        vm.label(address(conditionalTokens), "CT");
        vm.label(address(reality), "reality");
        vm.label(address(wrapped1155Factory), "wrapped 1155 factory");
        vm.label(address(collateralToken), "$COL");
    }
}

contract ConstructorTest is Base {
    function testConstructorSetsAttributes() public view {
        assertEq(
            address(factory.conditionalTokens()),
            address(conditionalTokens),
            "Market ConditionalTokens address mismatch"
        );
    }
}

contract CreateBadMarketTest is Base {
    uint256 constant DECISION_TEMPLATE_ID = 4242;
    uint256 constant METRIC_TEMPLATE_ID = 2424;
    string METADATA_URI = "ipfs://sfpi";

    function test0Outcomes(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime) public {
        string[] memory outcomeNames = new string[](0);
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(InvalidlessFlatCFMFactory.InvalidOutcomeCount.selector);
        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testTooManyOutcomes(
        uint32 openingTime,
        uint256 minValue,
        uint256 maxValue,
        uint32 scalarOpeningTime
    )
        public
    {
        // exceed factory.MAX_OUTCOME_COUNT()
        uint256 tooMany = factory.MAX_OUTCOME_COUNT() + 1;
        string[] memory outcomeNames = new string[](tooMany);

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(InvalidlessFlatCFMFactory.InvalidOutcomeCount.selector);
        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testTooLargeOutcomeName(
        uint32 openingTime,
        uint256 minValue,
        uint256 maxValue,
        uint32 scalarOpeningTime
    )
        public
    {
        // single outcome name exceeds length
        string[] memory outcomeNames = new string[](1);
        outcomeNames[0] = "01234567890123456789012345";

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidlessFlatCFMFactory.InvalidOutcomeNameLength.selector, "01234567890123456789012345"
            )
        );
        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
    }

    function testTooManyCreateScalarCalls(
        uint32 openingTime,
        uint256 minValue,
        uint256 maxValue,
        uint32 scalarOpeningTime
    )
        public
    {
        string[] memory outcomeNames = new string[](2);
        outcomeNames[0] = "1";
        outcomeNames[1] = "2";

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < decisionQuestionParams.outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        vm.expectRevert(InvalidlessFlatCFMFactory.NoConditionalScalarMarketToDeploy.selector);
        factory.createConditionalScalarMarket(cfm);
    }

    function testCreateScalarAlone() public {
        vm.expectRevert(InvalidlessFlatCFMFactory.NoConditionalScalarMarketToDeploy.selector);
        factory.createConditionalScalarMarket(FlatCFM(address(0xdeadbeef)));
    }

    function testRevertsIfBothDefaultPayoutsAreZero() public {
        string[] memory outcomeNames = new string[](1);
        outcomeNames[0] = "Test Outcome";

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: uint32(block.timestamp + 1000)});

        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 1000}),
            openingTime: uint32(block.timestamp + 2000)
        });

        vm.expectRevert(InvalidlessFlatCFMFactory.InvalidPayoutsCannotBeBothZero.selector);
        factory.createFlatCFM(
            oracleAdapter,
            42, // decisionTemplateId
            43, // metricTemplateId
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(0), uint256(0)], // defaultInvalidPayouts
            collateralToken,
            "ipfs://metadata"
        );
    }

    function testRevertsIfDefaultPayoutsSumOverflows() public {
        string[] memory outcomeNames = new string[](1);
        outcomeNames[0] = "Test Outcome";

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: uint32(block.timestamp + 1000)});

        GenericScalarQuestionParams memory genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 1000}),
            openingTime: uint32(block.timestamp + 2000)
        });

        uint256[2] memory overflowPayouts = [type(uint256).max, 1];

        vm.expectRevert();  // Will revert with arithmetic overflow
        factory.createFlatCFM(
            oracleAdapter,
            42, // decisionTemplateId
            43, // metricTemplateId
            decisionQuestionParams,
            genericScalarQuestionParams,
            overflowPayouts,
            collateralToken,
            "ipfs://metadata"
        );
    }
}

contract CreateMarketTestBase is Base {
    string[] outcomeNames;
    uint256 constant DECISION_TEMPLATE_ID = 42;
    uint256 constant METRIC_TEMPLATE_ID = 442;
    uint32 constant DECISION_OPENING_TIME = 1_739_577_600; // 2025-02-15
    string constant ROUND_NAME = "round";
    string constant METRIC_NAME = "metric";
    string constant START_DATE = "2025-02-16";
    string constant END_DATE = "2025-06-16";
    uint256 constant MIN_VALUE = 0;
    uint256 constant MAX_VALUE = 1_000_000;
    uint32 constant METRIC_OPENING_TIME = 1_750_118_400; // 2025-06-17
    string METADATA_URI = "ipfs://sfpi";

    bytes32 constant DECISION_QID = bytes32("decision question id");
    //bytes32 constant DECISION_CID = bytes32("decision condition id");
    bytes32 constant METRIC_QID = bytes32("conditional question id");
    //bytes32 constant METRIC_CID = bytes32("conditional condition id");
    bytes32 constant OUTCOME1_PARENT_COLLEC_ID = bytes32("cond 1 parent collection id");
    bytes32 constant SHORT_COLLEC_ID = bytes32("short collection id");
    uint256 constant SHORT_POSID = uint256(bytes32("short position id"));
    bytes32 constant LONG_COLLEC_ID = bytes32("long collection id");
    uint256 constant LONG_POSID = uint256(bytes32("long position id"));

    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams genericScalarQuestionParams;

    event FlatCFMCreated(address indexed market);
    event ConditionalMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    function setUp() public virtual override {
        super.setUp();

        outcomeNames.push("Project A");
        outcomeNames.push("Project B");
        outcomeNames.push("Project C");
        outcomeNames.push("Project D");

        decisionQuestionParams = FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: DECISION_OPENING_TIME});

        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: METRIC_OPENING_TIME
        });
    }

    function _getFirstConditionalScalarMarket() internal returns (InvalidlessConditionalScalarMarket) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)")) {
                // topics[2] because address is the second indexed param
                InvalidlessConditionalScalarMarket _icsm =
                    InvalidlessConditionalScalarMarket(address(uint160(uint256(logs[i].topics[2]))));
                (uint256 outcomeIndex) = abi.decode(logs[i].data, (uint256));
                if (outcomeIndex == 0) {
                    return _icsm;
                }
            }
        }
        revert("No ConditionalMarketCreated event found");
    }
}

contract CreateMarketTest is CreateMarketTestBase {
    using String31 for string;

    bytes32 constant CONDITION_ID = bytes32("some condition id");

    function testEmitsFlatCFMCreated() public {
        vm.recordLogs();

        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getConditionId.selector),
            abi.encode(CONDITION_ID)
        );

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        bytes32 eventSignature = keccak256("FlatCFMCreated(address,bytes32,address)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        bytes32 condId;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                address marketAddr = address(uint160(uint256(logs[i].topics[1])));
                if (marketAddr == address(cfm)) {
                    // We aren't mocking the condition ID here, so just check that we found the event
                    condId = abi.decode(logs[i].data, (bytes32));
                    found = true;
                }
            }
        }
        assertTrue(found, "FlatCFMCreated event not found");
        assertEq(condId, CONDITION_ID, "FlatCFMCreated event conditionId mismatch");
    }

    function testCreatesConditionalMarkets() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        vm.recordLogs();
        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        bytes32 eventSignature = keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                address decisionMkt = address(uint160(uint256(logs[i].topics[1])));
                if (decisionMkt == address(cfm)) {
                    found++;
                }
            }
        }

        assertEq(found, 4, "Should emit 4 InvalidlessConditionalScalarMarketCreated events");
    }

    function testCallsAskDecisionQuestion() public {
        vm.expectCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            )
        );

        // Only need to create the FlatCFM to trigger askDecisionQuestion.
        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
    }

    function testCallsPrepareConditionWithQuestionId() public {
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            ),
            abi.encode(DECISION_QID)
        );

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        // The factory sets up the decision condition for the FlatCFM contract:
        assertEq(conditionalTokens._test_prepareCondition_oracle(DECISION_QID), address(cfm));
    }

    function testEmitsConditionalMarketCreated() public {
        vm.recordLogs();

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        bytes32 eventSignature = keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                if (address(cfm) == address(uint160(uint256(logs[i].topics[1])))) {
                    found++;
                }
            }
        }
        assertEq(found, 4);
    }

    function testCallsAskMetricQuestion() public {
        vm.expectCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askMetricQuestion.selector,
                METRIC_TEMPLATE_ID,
                genericScalarQuestionParams,
                outcomeNames[1]
            )
        );

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }
    }

    function testCallsPrepareConditionForMetric() public {
        vm.expectCall(
            address(conditionalTokens), abi.encodeWithSelector(IConditionalTokens.prepareCondition.selector), 5
        );

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }
    }
}

contract CreateMarketDeploymentTestBase is CreateMarketTestBase {
    using String31 for string;

    bytes32 constant CONDITION_ID = "test condition id";

    bytes shortData;
    bytes longData;
    bytes invalidData;

    function setUp() public override {
        super.setUp();

        shortData = abi.encodePacked(
            string.concat(outcomeNames[0], "-Short").toString31(),
            string.concat(outcomeNames[0], "-ST").toString31(),
            uint8(18)
        );
        longData = abi.encodePacked(
            string.concat(outcomeNames[0], "-Long").toString31(),
            string.concat(outcomeNames[0], "-LG").toString31(),
            uint8(18)
        );
        invalidData = abi.encodePacked(
            string.concat(outcomeNames[0], "-Inv").toString31(),
            string.concat(outcomeNames[0], "-XX").toString31(),
            uint8(18)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askDecisionQuestion.selector),
            abi.encode(DECISION_QID)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(METRIC_QID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getConditionId.selector),
            abi.encode(CONDITION_ID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getCollectionId.selector, 0),
            abi.encode(OUTCOME1_PARENT_COLLEC_ID)
        );

        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getCollectionId.selector, OUTCOME1_PARENT_COLLEC_ID, CONDITION_ID, 1
            ),
            abi.encode(SHORT_COLLEC_ID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getPositionId.selector, collateralToken, SHORT_COLLEC_ID),
            abi.encode(SHORT_POSID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getCollectionId.selector, OUTCOME1_PARENT_COLLEC_ID, CONDITION_ID, 1 << 1
            ),
            abi.encode(LONG_COLLEC_ID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getPositionId.selector, collateralToken, LONG_COLLEC_ID),
            abi.encode(LONG_POSID)
        );
        vm.mockCall(
            address(wrapped1155Factory),
            abi.encodeWithSelector(
                IWrapped1155Factory.requireWrapped1155.selector, conditionalTokens, SHORT_POSID, shortData
            ),
            abi.encode(IERC20(address(0x42244224)))
        );
        vm.mockCall(
            address(wrapped1155Factory),
            abi.encodeWithSelector(
                IWrapped1155Factory.requireWrapped1155.selector, conditionalTokens, LONG_POSID, longData
            ),
            abi.encode(IERC20(address(0x24422442)))
        );
    }
}

contract CreateMarketDeploymentTest is CreateMarketDeploymentTestBase {
    function testDeploysAFlatCFM() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        assertEq(address(cfm.conditionalTokens()), address(conditionalTokens));
        assertEq(address(cfm.oracleAdapter()), address(oracleAdapter));
        assertEq(cfm.outcomeCount(), 4);
        assertEq(cfm.questionId(), DECISION_QID);
    }

    function testDeploysAConditionalScalarMarket() public {
        vm.recordLogs();
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }
        InvalidlessConditionalScalarMarket icsm1 = _getFirstConditionalScalarMarket();

        assertEq(address(icsm1.oracleAdapter()), address(oracleAdapter));
        assertEq(address(icsm1.conditionalTokens()), address(conditionalTokens), "CT mismatch");
        assertEq(address(icsm1.wrapped1155Factory()), address(wrapped1155Factory), "1155 factory mismatch");
        (bytes32 paramsQId, bytes32 paramsCId, bytes32 paramsColId, IERC20 paramsCollat) = icsm1.ctParams();
        assertEq(paramsQId, METRIC_QID, "metric q id mismatch");
        assertEq(paramsCId, CONDITION_ID, "metric condition id mismatch");
        assertEq(paramsColId, OUTCOME1_PARENT_COLLEC_ID, "metric parent collection id mismatch");
        assertEq(address(paramsCollat), address(collateralToken));
        (uint256 paramsMin, uint256 paramsMax) = icsm1.scalarParams();
        assertEq(paramsMin, MIN_VALUE);
        assertEq(paramsMax, MAX_VALUE);
        (bytes memory paramsSD, bytes memory paramsLD, uint256 paramsSPId, uint256 paramsLPId, IERC20 ws, IERC20 wl) =
            icsm1.wrappedCTData();
        assertEq(paramsSD, shortData, "short token data should match");
        assertEq(paramsLD, longData, "long token data should match");
        assertEq(paramsSPId, SHORT_POSID);
        assertEq(paramsLPId, LONG_POSID);
        assertEq(address(ws), address(0x42244224));
        assertEq(address(wl), address(0x24422442));
    }
}

contract CreateMarketFuzzTest is CreateMarketTestBase {
    function testCreateMarket(uint256 outcomeCount) public {
        vm.assume(outcomeCount > 0 && outcomeCount <= factory.MAX_OUTCOME_COUNT());

        string[] memory outs = new string[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            outs[i] = Strings.toString(i);
        }

        FlatCFMQuestionParams memory decisionQP =
            FlatCFMQuestionParams({outcomeNames: outs, openingTime: decisionQuestionParams.openingTime});

        GenericScalarQuestionParams memory metricQP = GenericScalarQuestionParams({
            scalarParams: ScalarParams({
                minValue: genericScalarQuestionParams.scalarParams.minValue,
                maxValue: genericScalarQuestionParams.scalarParams.maxValue
            }),
            openingTime: genericScalarQuestionParams.openingTime
        });

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter, 4242, 2424, decisionQP, metricQP, [uint256(1), uint256(3)], collateralToken, "ipfs://hello"
        );
        assertTrue(address(cfm) != address(0), "CFM should not be zero address");

        vm.recordLogs();
        for (uint256 i = 0; i < outcomeCount; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("InvalidlessConditionalScalarMarketCreated(address,address,uint256)")) {
                address parent = address(uint160(uint256(logs[i].topics[1])));
                if (parent == address(cfm)) found++;
            }
        }
        assertEq(found, outcomeCount, "Number of conditional markets does not match outcomeCount");
    }
}

contract PassValueToOracleAdapterTest is CreateMarketDeploymentTestBase {
    function testCreateFlatCFMForwardsPayment() public {
        uint256 sendValue = 0.05 ether;

        vm.expectCall(
            address(oracleAdapter),
            sendValue,
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            )
        );

        factory.createFlatCFM{value: sendValue}(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
    }

    function testCreateFlatCFMNoPayment() public {
        vm.expectCall(
            address(oracleAdapter),
            0,
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            )
        );

        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
    }

    function testCreateFlatCFMWithoutEnoughPaymentReverts() public {
        vm.mockCallRevert(
            address(oracleAdapter),
            0,
            abi.encodeWithSelector(FlatCFMRealityAdapter.askDecisionQuestion.selector),
            "ETH must be provided"
        );
        vm.expectRevert("ETH must be provided");
        factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );
    }

    function testCreateCSMForwardsPayment() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        uint256 sendValue = 0.05 ether;

        vm.expectCall(
            address(oracleAdapter),
            sendValue,
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askMetricQuestion.selector,
                METRIC_TEMPLATE_ID,
                genericScalarQuestionParams,
                decisionQuestionParams.outcomeNames[0]
            )
        );

        factory.createConditionalScalarMarket{value: sendValue}(cfm);

        vm.expectCall(
            address(oracleAdapter),
            sendValue,
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askMetricQuestion.selector,
                METRIC_TEMPLATE_ID,
                genericScalarQuestionParams,
                decisionQuestionParams.outcomeNames[1]
            )
        );

        factory.createConditionalScalarMarket{value: sendValue}(cfm);
    }

    function testCreateCSMNoPayment() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        vm.expectCall(
            address(oracleAdapter),
            0,
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askMetricQuestion.selector, METRIC_TEMPLATE_ID, genericScalarQuestionParams
            )
        );

        factory.createConditionalScalarMarket(cfm);
    }

    function testCreateCSMWithoutEnoughPaymentReverts() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        vm.mockCallRevert(
            address(oracleAdapter),
            0,
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            "ETH must be provided"
        );

        vm.expectRevert("ETH must be provided");
        factory.createConditionalScalarMarket(cfm);
    }
}

contract AskQuestionRevertsTest is Base {
    uint256 constant DECISION_TEMPLATE_ID = 999;
    uint256 constant METRIC_TEMPLATE_ID = 111;
    string[] outcomeNames;
    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams genericScalarQuestionParams;

    function setUp() public override {
        super.setUp();

        outcomeNames.push("project a");
        outcomeNames.push("project b");
        decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: uint32(block.timestamp + 1000)});
        genericScalarQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: 0, maxValue: 1000}),
            openingTime: uint32(block.timestamp + 2000)
        });
    }

    function testCreateFlatCFMRevertsIfAskQuestionReverts() public {
        deal(address(this), 1 ether);
        vm.mockCallRevert(
            address(oracleAdapter), 1 ether, FlatCFMRealityAdapter.askDecisionQuestion.selector, "TEST_ERR"
        );

        vm.expectRevert(bytes("TEST_ERR"));
        factory.createFlatCFM{value: 1 ether}(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            "ipfs://metadata"
        );
    }

    function testCreateConditionalScalarMarketRevertsIfAskQuestionReverts() public {
        deal(address(this), 1 ether);

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            "ipfs://metadata"
        );

        vm.mockCallRevert(address(oracleAdapter), 1 ether, FlatCFMRealityAdapter.askMetricQuestion.selector, "TEST_ERR");

        vm.expectRevert(bytes("TEST_ERR"));
        factory.createConditionalScalarMarket{value: 1 ether}(cfm);
    }
}

contract InvalidlessParamsTest is CreateMarketTestBase {
    function testDefaultInvalidPayoutsArePassedToCSM() public {
        uint256[2] memory defaultPayouts = [uint256(42), uint256(58)];

        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            defaultPayouts,
            collateralToken,
            METADATA_URI
        );

        vm.recordLogs();
        factory.createConditionalScalarMarket(cfm);

        InvalidlessConditionalScalarMarket icsm = _getFirstConditionalScalarMarket();
        assertEq(icsm.defaultInvalidPayouts(0), 42, "Short default payout mismatch");
        assertEq(icsm.defaultInvalidPayouts(1), 58, "Long default payout mismatch");
    }
}

contract DeploymentParamsTest is CreateMarketTestBase {
    function testDeploymentParamsCleanupAfterLastMarket() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        // Deploy all markets
        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        // Verify params are cleaned up
        (IERC20 collateralToken, uint256 metricTemplateId,, bytes32 decisionConditionId) = factory.paramsToDeploy(cfm);

        assertEq(address(collateralToken), address(0), "Collateral not cleaned up");
        assertEq(metricTemplateId, 0, "Template ID not cleaned up");
        assertEq(decisionConditionId, bytes32(0), "Condition ID not cleaned up");

        assertEq(factory.nextOutcomeToDeploy(cfm), 0, "Next outcome index not cleaned up");
    }

    function testRevertWhenDeployingMoreMarketsThanOutcomes() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        // Deploy all markets
        for (uint256 i = 0; i < outcomeNames.length; i++) {
            factory.createConditionalScalarMarket(cfm);
        }

        // Try to deploy one more
        vm.expectRevert(InvalidlessFlatCFMFactory.NoConditionalScalarMarketToDeploy.selector);
        factory.createConditionalScalarMarket(cfm);
    }

    function testNextOutcomeToDeployIncrementsCorrectly() public {
        FlatCFM cfm = factory.createFlatCFM(
            oracleAdapter,
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            genericScalarQuestionParams,
            [uint256(1), uint256(3)],
            collateralToken,
            METADATA_URI
        );

        for (uint256 i = 0; i < outcomeNames.length - 1; i++) {
            factory.createConditionalScalarMarket(cfm);
            assertEq(factory.nextOutcomeToDeploy(cfm), i + 1, "Next outcome index incorrect");
        }
    }
}
