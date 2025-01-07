// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

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
    DummyConditionalTokens public conditionalTokens;
    DummyRealityETH public reality;
    IWrapped1155Factory public wrapped1155Factory;
    IERC20 public collateralToken;

    uint32 constant QUESTION_TIMEOUT = 1000;
    uint256 constant MIN_BOND = 1000000000000;

    function setUp() public virtual {
        conditionalTokens = new DummyConditionalTokens();
        reality = new DummyRealityETH();
        wrapped1155Factory = new DummyWrapped1155Factory();
        oracleAdapter =
            new FlatCFMRealityAdapter(IRealityETH(address(reality)), address(0x00), QUESTION_TIMEOUT, MIN_BOND);
        collateralToken = new TestERC20();

        factory = new FlatCFMFactory(
            oracleAdapter,
            IConditionalTokens(address(conditionalTokens)),
            IWrapped1155Factory(address(wrapped1155Factory))
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
        assertEq(address(factory.oracleAdapter()), address(oracleAdapter), "Market oracle address mismatch");
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
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeCount.selector, 0));
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testTooManyOutcomes(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        string[] memory outcomeNames = new string[](factory.MAX_OUTCOMES() + 1);
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeCount.selector, factory.MAX_OUTCOMES() + 1));
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testTooLargeOutcomeName(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        string[] memory outcomeNames = new string[](1);
        outcomeNames[0] = "01234567890123456789012345";
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});
        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.expectRevert(
            abi.encodeWithSelector(FlatCFMFactory.InvalidOutcomeNameLength.selector, "01234567890123456789012345")
        );
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }
}

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
    string METADATA_URI = "ipfs://sfpi";

    bytes32 constant DECISION_QID = bytes32("decision question id");
    //bytes32 constant DECISION_CID = bytes32("decision condition id");
    bytes32 constant CONDITIONAL_QID = bytes32("conditional question id");
    //bytes32 constant CONDITIONAL_CID = bytes32("conditional condition id");
    bytes32 constant COND1_PARENT_COLLEC_ID = bytes32("cond 1 parent collection id");
    bytes32 constant SHORT_COLLEC_ID = bytes32("short collection id");
    uint256 constant SHORT_POSID = uint256(bytes32("short position id"));
    bytes32 constant LONG_COLLEC_ID = bytes32("long collection id");
    uint256 constant LONG_POSID = uint256(bytes32("long position id"));
    bytes32 constant INVALID_COLLEC_ID = bytes32("invalid collection id");
    uint256 constant INVALID_POSID = uint256(bytes32("invalid position id"));

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

        decisionQuestionParams = FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: DECISION_OPENING_TIME});

        conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: METRIC_OPENING_TIME
        });
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

contract CreateMarketTest is CreateMarketTestBase {
    using String31 for string;

    function testEmitsFlatCFMCreated() public {
        bool found;
        vm.recordLogs();

        FlatCFM cfm = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
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
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
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
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testEmitsConditionalMarketCreated() public {
        uint256 found;
        vm.recordLogs();

        FlatCFM cfm = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
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
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }

    function testCallsPrepareConditionForMetric() public {
        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.prepareCondition.selector, address(oracleAdapter)),
            5
        );
        factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );
    }
}

contract CreateMarketDeploymentTest is CreateMarketTestBase {
    using String31 for string;

    bytes32 decisionConditionId;
    bytes32 metricConditionId;
    bytes shortData;
    bytes longData;
    bytes invalidData;
    FlatCFM cfm;
    ConditionalScalarMarket csm1;

    function setUp() public override {
        super.setUp();

        decisionConditionId = keccak256(abi.encodePacked(address(oracleAdapter), DECISION_QID, outcomeNames.length + 1));
        //console.log("expected decision condition id");
        //console.logBytes32(DECISION_QID);
        //console.log(outcomeNames.length + 1);
        //console.logBytes32(decisionConditionId);
        metricConditionId = keccak256(abi.encodePacked(address(oracleAdapter), CONDITIONAL_QID, uint256(3)));

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
            abi.encode(decisionConditionId)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getConditionId.selector, address(oracleAdapter), metricConditionId, 3
            ),
            abi.encode(metricConditionId)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getCollectionId.selector, 0, decisionConditionId, 1),
            abi.encode(COND1_PARENT_COLLEC_ID)
        );

        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getCollectionId.selector, COND1_PARENT_COLLEC_ID, metricConditionId, 1
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
                IConditionalTokens.getCollectionId.selector, COND1_PARENT_COLLEC_ID, metricConditionId, 1 << 1
            ),
            abi.encode(LONG_COLLEC_ID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getPositionId.selector, collateralToken, LONG_COLLEC_ID),
            abi.encode(LONG_POSID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IConditionalTokens.getCollectionId.selector, COND1_PARENT_COLLEC_ID, metricConditionId, 1 << 2
            ),
            abi.encode(INVALID_COLLEC_ID)
        );
        vm.mockCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.getPositionId.selector, collateralToken, INVALID_COLLEC_ID),
            abi.encode(INVALID_POSID)
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

        vm.mockCall(
            address(wrapped1155Factory),
            abi.encodeWithSelector(
                IWrapped1155Factory.requireWrapped1155.selector, conditionalTokens, INVALID_POSID, invalidData
            ),
            abi.encode(IERC20(address(0xfefefefe)))
        );

        vm.recordLogs();
        cfm = factory.create(
            DECISION_TEMPLATE_ID,
            METRIC_TEMPLATE_ID,
            decisionQuestionParams,
            conditionalQuestionParams,
            collateralToken,
            METADATA_URI
        );

        csm1 = _getFirstConditionalScalarMarket();
    }

    function testDeploysAFlatCFM() public view {
        assertEq(address(cfm.conditionalTokens()), address(conditionalTokens));
        assertEq(address(cfm.oracleAdapter()), address(oracleAdapter));
        assertEq(cfm.outcomeCount(), 4);
        assertEq(cfm.questionId(), DECISION_QID);
        assertEq(cfm.conditionId(), decisionConditionId);
    }

    function testDeploysAConditionalScalarMarket() public view {
        assertEq(address(csm1.oracleAdapter()), address(oracleAdapter));
        assertEq(address(csm1.conditionalTokens()), address(conditionalTokens), "CT mismatch");
        assertEq(address(csm1.wrapped1155Factory()), address(wrapped1155Factory), "1155 factory mismatch");
        (bytes32 paramsQId, bytes32 paramsCId, bytes32 paramsColId, IERC20 paramsCollat) = csm1.ctParams();
        assertEq(paramsQId, CONDITIONAL_QID, "metric q id mismatch");
        assertEq(paramsCId, metricConditionId, "metric condition id mismatch");
        assertEq(paramsColId, COND1_PARENT_COLLEC_ID, "metric parent collection id mismatch");
        assertEq(address(paramsCollat), address(collateralToken));
        (uint256 paramsMin, uint256 paramsMax) = csm1.scalarParams();
        assertEq(paramsMin, MIN_VALUE);
        assertEq(paramsMax, MAX_VALUE);
        (
            bytes memory paramsSD,
            bytes memory paramsLD,
            bytes memory paramsID,
            uint256 paramsSPId,
            uint256 paramsLPId,
            uint256 paramsIPId,
            IERC20 ws,
            IERC20 wl,
            IERC20 wi
        ) = csm1.wrappedCTData();
        assertEq(paramsSD, shortData, "short token data should match");
        assertEq(paramsLD, longData, "long token data should match");
        assertEq(paramsID, invalidData, "invalid token data should match");
        assertEq(paramsSPId, SHORT_POSID);
        assertEq(paramsLPId, LONG_POSID);
        assertEq(paramsIPId, INVALID_POSID);
        assertEq(address(ws), address(0x42244224));
        assertEq(address(wl), address(0x24422442));
        assertEq(address(wi), address(0xfefefefe));
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
            FlatCFMQuestionParams({outcomeNames: outcomeNames, openingTime: openingTime});

        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        vm.recordLogs();
        FlatCFM cfm = factory.create(
            4242, 2424, decisionQuestionParams, conditionalQuestionParams, collateralToken, "ipfs://hello"
        );

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
