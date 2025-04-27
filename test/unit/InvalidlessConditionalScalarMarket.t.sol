// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import {IERC20Errors} from "@openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import "src/invalidless/InvalidlessConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyFlatCFMOracleAdapter} from "./dummy/FlatCFMOracleAdapter.sol";
import {DummyERC20} from "./dummy/ERC20.sol";

contract Base is Test {
    FlatCFMOracleAdapter oracleAdapter;
    IConditionalTokens conditionalTokens;
    IWrapped1155Factory wrapped1155Factory;

    InvalidlessConditionalScalarMarket icsm;

    IERC20 collateralToken;
    IERC20 shortToken;
    IERC20 longToken;
    IERC20 invalidToken;

    address constant USER = address(0x1111);

    uint256 constant DEAL = 10;
    bytes32 constant QUESTION_ID = bytes32("some question id");
    bytes32 constant CONDITION_ID = bytes32("some condition id");
    bytes32 constant PARENT_COLLECTION_ID = bytes32("someParentCollectionId");
    uint256 constant MIN_VALUE = 1000;
    uint256 constant MAX_VALUE = 11000;

    function setUp() public virtual {
        // 1. Deploy or mock the external dependencies
        oracleAdapter = new DummyFlatCFMOracleAdapter();
        conditionalTokens = new DummyConditionalTokens();
        wrapped1155Factory = new DummyWrapped1155Factory();
        collateralToken = new DummyERC20("Collateral", "COL");
        shortToken = new DummyERC20("Short", "ST");
        longToken = new DummyERC20("Long", "LG");
        invalidToken = new DummyERC20("Invalid", "XX");

        // 2. Deploy the InvalidlessConditionalScalarMarket
        icsm = new InvalidlessConditionalScalarMarket();
        icsm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            ConditionalScalarCTParams({
                questionId: QUESTION_ID,
                conditionId: CONDITION_ID,
                parentCollectionId: PARENT_COLLECTION_ID,
                collateralToken: collateralToken
            }),
            ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            InvalidlessWrappedConditionalTokensData({
                shortData: "",
                longData: "",
                shortPositionId: 1,
                longPositionId: 2,
                wrappedShort: shortToken,
                wrappedLong: longToken
            }),
            [uint256(1), uint256(3)]
        );
    }
}

// RESOLVE
// ----------------------------------------------------
contract ResolveTest is Base {
    function testResolveGoodAnswerCallsReportPayouts() public {
        uint256 answer = 9000;

        uint256[] memory expectedPayout = new uint256[](2);
        expectedPayout[0] = 2000;
        expectedPayout[1] = 8000;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        icsm.resolve();
    }

    function testResolveAboveMaxAnswerReportsPayouts() public {
        uint256 answer = 1000000;

        uint256[] memory expectedPayout = new uint256[](2);
        expectedPayout[0] = 0;
        expectedPayout[1] = 1;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        icsm.resolve();
    }

    function testResolveBelowMinAnswerReportsPayouts() public {
        uint256 answer = 0;

        uint256[] memory expectedPayout = new uint256[](2);
        expectedPayout[0] = 1;
        expectedPayout[1] = 0;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        icsm.resolve();
    }

    function testResolveInvalidReturnsDefault() public {
        bytes32 answer = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        uint256[] memory expectedPayout = new uint256[](2);
        expectedPayout[0] = 1;
        expectedPayout[1] = 3;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );
        vm.mockCall(
            address(oracleAdapter), abi.encodeWithSelector(FlatCFMOracleAdapter.isInvalid.selector), abi.encode(true)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        icsm.resolve();
    }

    function testResolveRevertsWithRevertingGetAnswer() public {
        vm.mockCallRevert(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            "whatever"
        );

        vm.expectRevert("whatever");
        icsm.resolve();
    }
}
