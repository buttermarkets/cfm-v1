// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/src/Test.sol";
import "@openzeppelin-contracts/proxy/Clones.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/utils/Strings.sol";

import "src/FlatCFMFactory.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMRealityAdapter.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/libs/String31.sol";

import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyRealityETH} from "./dummy/RealityETH.sol";

contract TestERC20 is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000e18);
    }
}

contract Base is Test {
    FlatCFMFactory public factory;
    // This could be a dummy.
    FlatCFMRealityAdapter public oracleAdapter;
    IConditionalTokens public conditionalTokens;
    DummyRealityETH public oracle;
    IWrapped1155Factory public wrapped1155Factory;
    IERC20 public collateralToken;

    function setUp() public virtual {
        conditionalTokens = new DummyConditionalTokens();
        oracle = new DummyRealityETH();
        wrapped1155Factory = new DummyWrapped1155Factory();
        oracleAdapter = new FlatCFMRealityAdapter(IRealityETH(address(oracle)), address(0x00), 1000, 10000000000);
        collateralToken = new TestERC20();

        factory = new FlatCFMFactory(
            oracleAdapter,
            IConditionalTokens(address(conditionalTokens)),
            IWrapped1155Factory(address(wrapped1155Factory))
        );

        vm.label(address(factory), "factory");
        vm.label(address(oracleAdapter), "oracle adapter");
        vm.label(address(conditionalTokens), "CT");
        vm.label(address(oracle), "oracle");
        vm.label(address(wrapped1155Factory), "wrapped 1155 factory");
        vm.label(address(collateralToken), "$COL");
    }
}

contract ConstructorTest is Base {
    function testConstructorSetsAttributes() public view {
        assertEq(address(factory.oracleAdapter()), address(oracleAdapter), "Market oracle address mismatch");
        assertEq(
            address(factory.conditionalTokens()),
            address(conditionalTokens),
            "Market ConditionalTokens address mismatch"
        );
    }
}

contract CreateBadMarketTest is Base {
    function test0Outcomes(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime) public {
        string[] memory outcomeNames = new string[](0);
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });
        uint256 decisionTemplateId = 4242;
        uint256 metricTemplateId = 2424;

        vm.expectRevert(abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeCount.selector, 0));
        factory.create(
            decisionTemplateId, metricTemplateId, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }

    function testTooManyOutcomes(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        string[] memory outcomeNames = new string[](factory.MAX_OUTCOMES() + 1);
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });
        uint256 decisionTemplateId = 4242;
        uint256 metricTemplateId = 2424;

        vm.expectRevert(abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeCount.selector, factory.MAX_OUTCOMES() + 1));
        factory.create(
            decisionTemplateId, metricTemplateId, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }

    function testTooLargeOutcomeName(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        string[] memory outcomeNames = new string[](1);
        outcomeNames[0] = "01234567890123456789012345";
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });
        uint256 decisionTemplateId = 4242;
        uint256 metricTemplateId = 2424;

        vm.expectRevert(
            abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeNameLength.selector, "01234567890123456789012345")
        );
        factory.create(
            decisionTemplateId, metricTemplateId, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }
}

// XXX test create with same params still works: uses the same question
// XXX test create with same params still works: uses the same condition
// XXX test create another Factory and adapter then create with same params still works: same question
// XXX test create another Factory and adapter then create with same params still works: different condition
// XXX test create another Factory and same adapter then create with same params still works: same condition
contract CreateMarketTestBase is Base {
    string[] outcomeNames;
    uint256 constant DECISION_TEMPLATE_ID = 42;
    uint256 constant METRIC_TEMPLATE_ID = 442;
    uint32 constant DECISION_OPENING_TIME = 1739577600; // 2025-02-15
    string constant ROUND_NAME = "round";
    string constant METRIC_NAME = "metric";
    string constant START_DATE = "2025-02-16";
    string constant END_DATE = "2025-06-16";
    uint256 constant MIN_VALUE = 0;
    uint256 constant MAX_VALUE = 1000000;
    uint32 constant METRIC_OPENING_TIME = 1750118400; // 2025-06-17

    bytes32 constant DECISION_QID = bytes32("decision question id");
    bytes32 constant DECISION_CID = bytes32("decision condition id");
    bytes32 constant CONDITIONAL_QID = bytes32("conditional question id");
    bytes32 constant CONDITIONAL_CID = bytes32("conditional condition id");
    bytes32 constant COND1_PARENT_COLLEC_ID = bytes32("cond 1 parent collection id");
    bytes32 constant SHORT_COLLEC_ID = bytes32("short collection id");
    uint256 constant SHORT_POSID = uint256(bytes32("short position id"));
    bytes32 constant LONG_COLLEC_ID = bytes32("long collection id");
    uint256 constant LONG_POSID = uint256(bytes32("long position id"));

    FlatCFMQuestionParams decisionQuestionParams;
    GenericScalarQuestionParams conditionalQuestionParams;

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

        decisionQuestionParams = FlatCFMQuestionParams({
            roundName: ROUND_NAME,
            outcomeNames: outcomeNames,
            openingTime: DECISION_OPENING_TIME
        });

        conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: METRIC_NAME,
            startDate: START_DATE,
            endDate: END_DATE,
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: METRIC_OPENING_TIME
        });
    }
}

contract CreateMarketTest is CreateMarketTestBase {
    using String31 for string;

    function testEmitsFlatCFMCreated() public {
        bool found;
        vm.recordLogs();

        FlatCFM cfm = factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );

        bytes32 eventSignature = keccak256("FlatCFMCreated(address)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                found = found || (address(cfm) == address(uint160(uint256(logs[i].topics[1]))));
            }
        }
        assertTrue(found);
    }

    function testCallsAskDecisionQuestion() public {
        vm.expectCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                FlatCFMRealityAdapter.askDecisionQuestion.selector, DECISION_TEMPLATE_ID, decisionQuestionParams
            )
        );
        factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
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
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.prepareCondition.selector,
                address(oracleAdapter),
                DECISION_QID,
                outcomeNames.length + 1
            )
        );
        factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }

    function testEmitsConditionalMarketCreated() public {
        uint256 found;
        vm.recordLogs();

        FlatCFM cfm = factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );

        bytes32 eventSignature = keccak256("ConditionalMarketCreated(address,address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                if (address(cfm) == address(uint160(uint256(logs[i].topics[1])))) found++;
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
                conditionalQuestionParams,
                outcomeNames[1]
            )
        );
        factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }

    function testCallsPrepareConditionForMetric() public {
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(CONDITIONAL_QID)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.prepareCondition.selector, address(oracleAdapter), CONDITIONAL_QID, 3
            )
        );
        factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );
    }
}

contract CreateMarketDeploymentTest is CreateMarketTestBase {
    using String31 for string;

    bytes shortData;
    bytes longData;
    FlatCFM cfm;
    ConditionalScalarMarket csm1;

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
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askDecisionQuestion.selector),
            abi.encode(DECISION_QID)
        );
        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMRealityAdapter.askMetricQuestion.selector),
            abi.encode(CONDITIONAL_QID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getConditionId.selector,
                address(oracleAdapter),
                DECISION_QID,
                outcomeNames.length + 1
            ),
            abi.encode(DECISION_CID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getConditionId.selector, address(oracleAdapter), CONDITIONAL_QID, 3
            ),
            abi.encode(CONDITIONAL_CID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getCollectionId.selector, 0, DECISION_CID, 1),
            abi.encode(COND1_PARENT_COLLEC_ID)
        );

        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getCollectionId.selector, COND1_PARENT_COLLEC_ID, CONDITIONAL_CID, 1
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
                IConditionalTokens.getCollectionId.selector, COND1_PARENT_COLLEC_ID, CONDITIONAL_CID, 1 << 1
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

        vm.recordLogs();
        cfm = factory.create(
            DECISION_TEMPLATE_ID, METRIC_TEMPLATE_ID, decisionQuestionParams, conditionalQuestionParams, collateralToken
        );

        csm1 = _getFirstConditionalScalarMarket();
    }

    function testDeploysAFlatCFM() public view {
        assertEq(address(cfm.conditionalTokens()), address(conditionalTokens));
        assertEq(address(cfm.oracleAdapter()), address(oracleAdapter));
        assertEq(cfm.outcomeCount(), outcomeNames.length);
        assertEq(cfm.questionId(), DECISION_QID);
        assertEq(cfm.conditionId(), DECISION_CID);
    }

    function testDeploysAConditionalScalarMarketTokens() public view {
        assertEq(address(csm1.oracleAdapter()), address(oracleAdapter));
        assertEq(address(csm1.conditionalTokens()), address(conditionalTokens));
        assertEq(address(csm1.wrapped1155Factory()), address(wrapped1155Factory));
        (bytes32 paramsQId, bytes32 paramsCId, bytes32 paramsColId, IERC20 paramsCollat) = csm1.ctParams();
        assertEq(paramsQId, CONDITIONAL_QID);
        assertEq(paramsCId, CONDITIONAL_CID);
        assertEq(paramsColId, COND1_PARENT_COLLEC_ID);
        assertEq(address(paramsCollat), address(collateralToken));
        (uint256 paramsMin, uint256 paramsMax) = csm1.scalarParams();
        assertEq(paramsMin, MIN_VALUE);
        assertEq(paramsMax, MAX_VALUE);
        (bytes memory paramsSD, bytes memory paramsLD, uint256 paramsSPId, uint256 paramsLPId, IERC20 ws, IERC20 wl) =
            csm1.wrappedCTData();
        assertEq(paramsSD, shortData, "short token data should match");
        assertEq(paramsLD, longData, "long token data should match");
        assertEq(paramsSPId, SHORT_POSID);
        assertEq(paramsLPId, LONG_POSID);
        assertEq(address(ws), address(0x42244224));
        assertEq(address(wl), address(0x24422442));
    }

    function _getFirstConditionalScalarMarket() internal returns (ConditionalScalarMarket) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("ConditionalMarketCreated(address,address,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                // topics[2] because address is the second indexed param
                ConditionalScalarMarket _csm = ConditionalScalarMarket(address(uint160(uint256(logs[i].topics[2]))));
                (uint256 outcomeIndex) = abi.decode(logs[i].data, (uint256));
                if (outcomeIndex == 0) {
                    return _csm;
                }
            }
        }
        revert("No ConditionalMarketCreated event found");
    }
}

contract CreateMarketFuzzTest is Base {
    function testCreateMarket(
        uint256 outcomeCount,
        uint32 openingTime,
        uint256 minValue,
        uint256 maxValue,
        uint32 scalarOpeningTime
    ) public {
        vm.assume(outcomeCount > 0 && outcomeCount <= factory.MAX_OUTCOMES());

        string[] memory outcomeNames = new string[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            outcomeNames[i] = Strings.toString(i);
        }

        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});

        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.recordLogs();
        FlatCFM cfm = factory.create(4242, 2424, decisionQuestionParams, conditionalQuestionParams, collateralToken);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("ConditionalMarketCreated(address,address,uint256)");
        address firstCsmAddr;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                // topics[2] because address is the second indexed param
                firstCsmAddr = address(uint160(uint256(logs[i].topics[2])));
                break;
            }
        }
        assertTrue(firstCsmAddr != address(0), "No ConditionalMarket created");
        ConditionalScalarMarket firstCsm = ConditionalScalarMarket(firstCsmAddr);

        assertTrue(address(cfm) != address(0), "Created market address should not be zero");

        assertEq(address(cfm.oracleAdapter()), address(oracleAdapter));
        assertEq(address(cfm.conditionalTokens()), address(conditionalTokens));
        assertEq(cfm.outcomeCount(), outcomeNames.length, "Incorrect number of conditional markets created");

        assertEq(address(firstCsm.oracleAdapter()), address(oracleAdapter));
        assertEq(address(firstCsm.conditionalTokens()), address(conditionalTokens));
        (uint256 minv, uint256 maxv) = firstCsm.scalarParams();
        assertEq(minv, conditionalQuestionParams.scalarParams.minValue);
        assertEq(maxv, conditionalQuestionParams.scalarParams.maxValue);
    }
}
