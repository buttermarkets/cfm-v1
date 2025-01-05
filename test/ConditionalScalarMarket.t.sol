// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";

import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import "src/interfaces/IConditionalTokens.sol";
import "src/interfaces/IWrapped1155Factory.sol";
import {DummyConditionalTokens} from "./dummy/ConditionalTokens.sol";
import {DummyWrapped1155Factory} from "./dummy/Wrapped1155Factory.sol";
import {DummyFlatCFMOracleAdapter} from "./dummy/FlatCFMOracleAdapter.sol";
import {DummyERC20} from "./dummy/ERC20.sol";

contract BaseTest is Test {
    FlatCFMOracleAdapter oracleAdapter;
    IConditionalTokens conditionalTokens;
    IWrapped1155Factory wrapped1155Factory;

    ConditionalScalarMarket csm;

    IERC20 collateralToken;
    IERC20 shortToken;
    IERC20 longToken;

    address user = address(0x1111);

    uint256 constant DEAL = 10;

    function setUp() public virtual {
        // 1. Deploy or mock the external dependencies
        oracleAdapter = new DummyFlatCFMOracleAdapter();
        conditionalTokens = new DummyConditionalTokens();
        wrapped1155Factory = new DummyWrapped1155Factory();
        collateralToken = new DummyERC20("Collateral", "COL");
        shortToken = new DummyERC20("Short", "ST");
        longToken = new DummyERC20("Long", "LG");

        // 2. Deploy the ConditionalScalarMarket
        csm = new ConditionalScalarMarket();
        csm.initialize(
            oracleAdapter,
            conditionalTokens,
            wrapped1155Factory,
            ConditionalScalarCTParams({
                questionId: bytes32("someQuestionId"),
                conditionId: bytes32("someConditionId"),
                parentCollectionId: bytes32("someParentCollectionId"),
                collateralToken: collateralToken
            }),
            ScalarParams({minValue: 10, maxValue: 1000}),
            WrappedConditionalTokensData({
                shortData: "",
                longData: "",
                shortPositionId: 1,
                longPositionId: 2,
                wrappedShort: IERC20(address(shortToken)),
                wrappedLong: IERC20(address(longToken))
            })
        );
    }
}

// TODO add Split.

contract Mergetest is BaseTest {
    function setUp() public override {
        super.setUp();

        deal(address(shortToken), user, DEAL);
        deal(address(longToken), user, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 amount) public {
        bound(amount, 0, DEAL);
        // Intercept shortToken.transferFrom(...) call; return false => fail
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), amount),
            abi.encode(false) // cause revert
        );

        vm.startPrank(user);
        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedShortTransferFailed.selector,
                address(shortToken),
                user,
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
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), amount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), amount),
            abi.encode(false) // fail
        );

        vm.startPrank(user);
        shortToken.approve(address(csm), amount);
        longToken.approve(address(csm), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedLongTransferFailed.selector,
                address(longToken),
                user,
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

        deal(address(shortToken), user, DEAL);
        deal(address(longToken), user, DEAL);
    }

    function testRevertIfShortTransferFails(uint256 shortAmount, uint256 longAmount) public {
        bound(shortAmount, 0, DEAL);
        bound(longAmount, 0, DEAL);
        // Intercept shortToken.transferFrom(...) call; return false => fail
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), shortAmount),
            abi.encode(false) // cause revert
        );

        vm.startPrank(user);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedShortTransferFailed.selector,
                address(shortToken),
                user,
                address(csm),
                uint256(shortAmount)
            )
        );
        csm.redeem(shortAmount, longAmount);
        vm.stopPrank();
    }

    function testRevertIfLongTransferFails(uint256 shortAmount, uint256 longAmount) public {
        bound(shortAmount, 0, DEAL);
        bound(longAmount, 0, DEAL);
        // We'll let short transfer succeed, but mock the long transfer to fail.
        vm.mockCall(
            address(shortToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), shortAmount),
            abi.encode(true) // success
        );
        vm.mockCall(
            address(longToken),
            abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(csm), longAmount),
            abi.encode(false) // fail
        );

        vm.startPrank(user);
        shortToken.approve(address(csm), shortAmount);
        longToken.approve(address(csm), longAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ConditionalScalarMarket.WrappedLongTransferFailed.selector,
                address(longToken),
                user,
                address(csm),
                uint256(longAmount)
            )
        );
        csm.redeem(shortAmount, longAmount);
        vm.stopPrank();
    }
}
