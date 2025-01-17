// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import {IERC20Errors} from "@openzeppelin-contracts/interfaces/draft-IERC6093.sol";

import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyFlatCFMOracleAdapter} from "./dummy/FlatCFMOracleAdapter.sol";
import {DummyERC20} from "./dummy/ERC20.sol";

// TODO Integration tests for split/m/r in all different state cases: DecisionResolved? x
// ConditionalResolved?
// TODO Integration test: user 1 splits, resolve at Invalid case, user 2 redeems,
// user 1 should still be able to redeem what was splitted.

contract Base is Test {
    FlatCFMOracleAdapter oracleAdapter;
    IConditionalTokens conditionalTokens;
    IWrapped1155Factory wrapped1155Factory;

    ConditionalScalarMarket csm;

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

        // 2. Deploy the ConditionalScalarMarket
        csm = new ConditionalScalarMarket();
        csm.initialize(
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
            WrappedConditionalTokensData({
                shortData: "",
                longData: "",
                invalidData: "",
                shortPositionId: 1,
                longPositionId: 2,
                invalidPositionId: 2,
                wrappedShort: shortToken,
                wrappedLong: longToken,
                wrappedInvalid: invalidToken
            })
        );
    }
}

// ----------------------------------------------------
// SPLIT: ERC1155 outcome transfer fails
// ----------------------------------------------------
contract SplitDecisionOutcomeTransferTest is Base {
    function setUp() public override {
        super.setUp();
        deal(address(collateralToken), USER, DEAL);
    }

    function testRevertIfDecisionOutcomeTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);
        // The first step in split is transferring the decision outcome ERC1155 from USER => csm
        // We mock it to fail.
        vm.mockCallRevert(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IERC1155.safeTransferFrom.selector,
                USER,
                address(csm),
                conditionalTokens.getPositionId(collateralToken, PARENT_COLLECTION_ID),
                amount,
                ""
            ),
            "transfer fail"
        );

        vm.startPrank(USER);
        vm.expectRevert("transfer fail");
        csm.split(amount);
        vm.stopPrank();
    }
}

// ----------------------------------------------------
// SPLIT: Non-compliant ERC20
// ----------------------------------------------------
contract SplitFalseERC20TransfersTest is Base {
    function setUp() public override {
        super.setUp();
        deal(address(shortToken), address(csm), DEAL);
        deal(address(longToken), address(csm), DEAL);
        deal(address(invalidToken), address(csm), DEAL);
        vm.mockCall(address(conditionalTokens), IERC1155.safeTransferFrom.selector, abi.encode(0));
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);

        vm.mockCall(
            address(shortToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(false)
        );

        vm.startPrank(USER);
        vm.expectRevert(ConditionalScalarMarket.WrappedShortTransferFailed.selector);
        csm.split(amount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);

        vm.mockCall(
            address(shortToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(true)
        );
        vm.mockCall(
            address(longToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(false)
        );

        vm.startPrank(USER);
        vm.expectRevert(ConditionalScalarMarket.WrappedLongTransferFailed.selector);
        csm.split(amount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);

        vm.mockCall(
            address(shortToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(true)
        );
        vm.mockCall(
            address(longToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(true)
        );
        vm.mockCall(
            address(invalidToken), abi.encodeWithSelector(IERC20.transfer.selector, USER, amount), abi.encode(false)
        );

        vm.startPrank(USER);
        vm.expectRevert(ConditionalScalarMarket.WrappedInvalidTransferFailed.selector);
        csm.split(amount);
        vm.stopPrank();
    }
}

// ----------------------------------------------------
// SPLIT: Compliant ERC20
// ----------------------------------------------------
contract SplitERC20TransferTest is Base {
    function setUp() public override {
        super.setUp();
        deal(address(shortToken), address(csm), DEAL);
        deal(address(longToken), address(csm), DEAL);
        deal(address(invalidToken), address(csm), DEAL);
        vm.mockCall(address(conditionalTokens), IERC1155.safeTransferFrom.selector, abi.encode(0));
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);
        vm.prank(address(csm));
        shortToken.transfer(makeAddr("burn"), DEAL);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(csm), 0, amount));
        vm.prank(USER);
        csm.split(amount);
    }

    function testRevertIfLongTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);
        vm.prank(address(csm));
        longToken.transfer(makeAddr("burn"), DEAL);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(csm), 0, amount));
        vm.prank(USER);
        csm.split(amount);
    }

    function testRevertIfInvalidTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);
        vm.prank(address(csm));
        invalidToken.transfer(makeAddr("burn"), DEAL);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(csm), 0, amount));
        vm.prank(USER);
        csm.split(amount);
    }
}

// ----------------------------------------------------
// MERGE: Non-compliant ERC20
// ----------------------------------------------------
contract MergeFalseEC20TransfersTest is Base {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);
        // Intercept shortToken.transferFrom(...) call; return false => fail
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(false) // cause revert
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(ConditionalScalarMarket.WrappedShortTransferFailed.selector);
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);
        // We'll let short transfer succeed, but mock the long transfer to fail.
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(false) // fail
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(ConditionalScalarMarket.WrappedLongTransferFailed.selector);
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 amount) public {
        amount = bound(amount, 0, DEAL);
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(true)
        );
        vm.mockCall(
            address(invalidToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), amount),
            abi.encode(false)
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(ConditionalScalarMarket.WrappedInvalidTransferFailed.selector);
        csm.merge(amount);
        vm.stopPrank();
    }
}

// ----------------------------------------------------
// MERGE: Compliant ERC20
// ----------------------------------------------------
contract MergeRevertingERC20TransfersTest is Base {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);

        vm.startPrank(USER);

        shortToken.transfer(makeAddr("burn"), DEAL);

        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, amount)
        );
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);

        vm.startPrank(USER);

        longToken.transfer(makeAddr("burn"), DEAL);

        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, amount)
        );
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 amount) public {
        amount = bound(amount, 1, DEAL);

        vm.startPrank(USER);

        invalidToken.transfer(makeAddr("burn"), DEAL);

        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);
        invalidToken.approve(address(csm), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, amount)
        );
        csm.merge(amount);
        vm.stopPrank();
    }
}

// TODO integration tests with ConditionalTokens with different amounts
contract RedeemBase is Base {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }
}

// ----------------------------------------------------
// REDEEM: General
// ----------------------------------------------------
contract RedeeemTest is RedeemBase {
    function testRedeemWithZeroAmounts() public {
        // Resolve condition first
        vm.startPrank(USER);
        // Redeem zero
        csm.redeem(0, 0, 0);
        vm.stopPrank();
    }

    function testPartialRedemptions_OnlyInvalid(uint256 invalidAmount) public {
        invalidAmount = bound(invalidAmount, 0, DEAL);
        vm.startPrank(USER);
        invalidToken.approve(address(csm), invalidAmount);
        csm.redeem(0, 0, invalidAmount);
        vm.stopPrank();
    }

    function testRedemption(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        shortAmount = bound(shortAmount, 0, DEAL);
        longAmount = bound(longAmount, 0, DEAL);
        invalidAmount = bound(invalidAmount, 0, DEAL);
        vm.startPrank(USER);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);
        invalidToken.approve(address(csm), invalidAmount);
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }
}

// ----------------------------------------------------
// REDEEM: Compliant ERC20
// ----------------------------------------------------
contract RedeemRevertingERC20TransfersTest is Base {
    function setUp() public override {
        super.setUp();
        // user has some tokens, but we can forcibly cause revert by draining them
        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }

    function testRevertIfShortInsufficientBalance(uint256 shortAmount) public {
        shortAmount = bound(shortAmount, 1, DEAL);

        vm.startPrank(USER);
        shortToken.transfer(makeAddr("burn"), DEAL); // drain user
        shortToken.approve(address(csm), shortAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, shortAmount)
        );
        csm.redeem(shortAmount, 0, 0);
        vm.stopPrank();
    }

    function testRevertIfLongInsufficientBalance(uint256 longAmount) public {
        longAmount = bound(longAmount, 1, DEAL);

        vm.startPrank(USER);
        longToken.transfer(makeAddr("burn"), DEAL);
        longToken.approve(address(csm), longAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, longAmount)
        );
        csm.redeem(0, longAmount, 0);
        vm.stopPrank();
    }

    function testRevertIfInvalidInsufficientBalance(uint256 invalidAmount) public {
        invalidAmount = bound(invalidAmount, 1, DEAL);

        vm.startPrank(USER);
        invalidToken.transfer(makeAddr("burn"), DEAL);
        invalidToken.approve(address(csm), invalidAmount);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(USER), 0, invalidAmount)
        );
        csm.redeem(0, 0, invalidAmount);
        vm.stopPrank();
    }
}

// ----------------------------------------------------
// REDEEM: Non-compliant ERC20
// ----------------------------------------------------
contract RedeemFalseERC20TransfersTest is RedeemBase {
    function testRevertIfShortTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        shortAmount = bound(shortAmount, 0, DEAL);
        longAmount = bound(longAmount, 0, DEAL);
        invalidAmount = bound(invalidAmount, 0, DEAL);
        // Intercept shortToken.transferFrom(...) call; return false => fail
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), shortAmount),
            abi.encode(false) // cause revert
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);
        invalidToken.approve(address(csm), invalidAmount);

        vm.expectRevert(ConditionalScalarMarket.WrappedShortTransferFailed.selector);
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        shortAmount = bound(shortAmount, 0, DEAL);
        longAmount = bound(longAmount, 0, DEAL);
        invalidAmount = bound(invalidAmount, 0, DEAL);
        // We'll let short transfer succeed, but mock the long transfer to fail.
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), shortAmount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), longAmount),
            abi.encode(false) // fail
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);
        invalidToken.approve(address(csm), invalidAmount);

        vm.expectRevert(ConditionalScalarMarket.WrappedLongTransferFailed.selector);
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        shortAmount = bound(shortAmount, 0, DEAL);
        longAmount = bound(longAmount, 0, DEAL);
        invalidAmount = bound(invalidAmount, 0, DEAL);
        // We'll let short transfer succeed, but mock the long transfer to fail.
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), shortAmount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), longAmount),
            abi.encode(true)
        );

        vm.mockCall(
            address(invalidToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, USER, address(csm), invalidAmount),
            abi.encode(false) // fail
        );

        vm.startPrank(USER);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);
        invalidToken.approve(address(csm), invalidAmount);

        vm.expectRevert(ConditionalScalarMarket.WrappedInvalidTransferFailed.selector);
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }
}

contract RedeemBookeepingTest is RedeemBase {
    uint256 constant DECISION_POS_ID = 1234;

    function testMockedBookkeeping() public {
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(1000);
        mocks[1] = abi.encode(1200);
        vm.mockCalls(
            address(conditionalTokens),
            abi.encodeWithSelector(IERC1155.balanceOf.selector, address(csm), DECISION_POS_ID),
            mocks
        );
        vm.mockCall(address(conditionalTokens), IConditionalTokens.getPositionId.selector, abi.encode(DECISION_POS_ID));
        vm.mockCall(address(conditionalTokens), IERC1155.safeTransferFrom.selector, abi.encode(0));

        uint256 expectedRedeemed = 200;

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(
                IERC1155.safeTransferFrom.selector, address(csm), USER, DECISION_POS_ID, expectedRedeemed, ""
            )
        );

        vm.startPrank(USER);
        // We don't care about the amounts here because everything's mocked.
        csm.redeem(0, 0, 0);
        vm.stopPrank();
    }
}
// ====================================================

// ----------------------------------------------------
// RESOLVE
// ----------------------------------------------------
contract ResolveTest is Base {
    function testResolveGoodAnswerCallsReportPayouts() public {
        uint256 answer = 9000;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 2000;
        expectedPayout[1] = 8000;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        csm.resolve();
    }

    function testResolveAboveMaxAnswerReportsPayouts() public {
        uint256 answer = 1000000;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 0;
        expectedPayout[1] = 1;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        csm.resolve();
    }

    function testResolveBelowMinAnswerReportsPayouts() public {
        uint256 answer = 0;

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[0] = 1;
        expectedPayout[1] = 0;
        expectedPayout[2] = 0;

        vm.mockCall(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            abi.encode(answer)
        );

        vm.expectCall(
            address(conditionalTokens),
            abi.encodeWithSelector(IConditionalTokens.reportPayouts.selector, QUESTION_ID, expectedPayout)
        );
        csm.resolve();
    }

    function testResolveInvalidReturnsLastPayout() public {
        bytes32 answer = bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        uint256[] memory expectedPayout = new uint256[](3);
        expectedPayout[2] = 1;

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
        csm.resolve();
    }

    function testResolveRevertsWithRevertingGetAnswer() public {
        vm.mockCallRevert(
            address(oracleAdapter),
            abi.encodeWithSelector(FlatCFMOracleAdapter.getAnswer.selector, QUESTION_ID),
            "whatever"
        );

        vm.expectRevert("whatever");
        csm.resolve();
    }
}
