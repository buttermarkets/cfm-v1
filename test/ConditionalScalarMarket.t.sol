// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import "forge-std/src/Test.sol";

import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyFlatCFMOracleAdapter} from "./dummy/FlatCFMOracleAdapter.sol";
import {DummyERC20} from "./dummy/ERC20.sol";

// TODO test split
// TODO Integration tests for split/m/r in all different state cases: DecisionResolved? x
// ConditionalResolved?
// TODO Integration test: user 1 splits, resolve at Invalid case, user 2 redeems, user 1 should still be able to redeem what was splitted.

contract BaseTest is Test {
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
                wrappedShort: IERC20(address(shortToken)),
                wrappedLong: IERC20(address(longToken)),
                wrappedInvalid: IERC20(address(invalidToken))
            })
        );
    }
}

contract Mergetest is BaseTest {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        bound(amount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedShortTransferFailed.selector,
                address(shortToken),
                USER,
                address(csm),
                uint256(amount)
            )
        );
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 amount) public {
        bound(amount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedLongTransferFailed.selector,
                address(longToken),
                USER,
                address(csm),
                uint256(amount)
            )
        );
        csm.merge(amount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 amount) public {
        bound(amount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedInvalidTransferFailed.selector,
                address(invalidToken),
                USER,
                address(csm),
                uint256(amount)
            )
        );
        csm.merge(amount);
        vm.stopPrank();
    }
}

// TODO test the internal bookeeping logic (before/after).
contract Redeemtest is BaseTest {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), USER, DEAL);
        deal(address(longToken), USER, DEAL);
        deal(address(invalidToken), USER, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        bound(shortAmount, 0, DEAL);
        bound(longAmount, 0, DEAL);
        bound(invalidAmount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedShortTransferFailed.selector,
                address(shortToken),
                USER,
                address(csm),
                uint256(shortAmount)
            )
        );
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        bound(shortAmount, 0, DEAL);
        bound(longAmount, 0, DEAL);
        bound(invalidAmount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedLongTransferFailed.selector,
                address(longToken),
                USER,
                address(csm),
                uint256(longAmount)
            )
        );
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }

    function testRevertIfInvalidTransferFails(uint256 shortAmount, uint256 longAmount, uint256 invalidAmount) public {
        bound(shortAmount, 0, DEAL);
        bound(longAmount, 0, DEAL);
        bound(invalidAmount, 0, DEAL);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedInvalidTransferFailed.selector,
                address(invalidToken),
                USER,
                address(csm),
                uint256(invalidAmount)
            )
        );
        csm.redeem(shortAmount, longAmount, invalidAmount);
        vm.stopPrank();
    }
}

contract ResolveTest is BaseTest {
    function testResolveToAdapter() public {
        vm.expectCall(
            address(oracleAdapter),
            abi.encodeWithSelector(
                DummyFlatCFMOracleAdapter.reportMetricPayouts.selector,
                conditionalTokens,
                QUESTION_ID,
                MIN_VALUE,
                MAX_VALUE
            )
        );
        csm.resolve();
    }
}
