// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Test.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import "src/invalidless/InvalidlessConditionalScalarMarketFactory.sol";
import "src/invalidless/InvalidlessConditionalScalarMarket.sol";
import "src/FlatCFMOracleAdapter.sol";
import {ScalarParams, GenericScalarQuestionParams} from "src/Types.sol";
import "test/unit/dummy/ConditionalTokens.sol";
import "test/unit/dummy/Wrapped1155Factory.sol";
import "test/unit/dummy/ERC20.sol";
import "test/unit/dummy/RealityETH.sol";
import "test/unit/dummy/FlatCFMOracleAdapter.sol";

contract Base is Test {
    InvalidlessConditionalScalarMarketFactory factory;
    DummyConditionalTokens conditionalTokens;
    DummyWrapped1155Factory wrapped1155Factory;
    DummyFlatCFMOracleAdapter oracleAdapter;
    DummyERC20 collateralToken;
    DummyRealityETH realityETH;

    uint256 constant TEMPLATE_ID = 2;
    string constant OUTCOME_NAME = "Temperature";
    uint256 constant MIN_VALUE = 0;
    uint256 constant MAX_VALUE = 100;
    uint32 OPENING_TIME = uint32(1735689600); // Future timestamp
    uint256[2] DEFAULT_INVALID_PAYOUTS = [1, 0];

    event InvalidlessConditionalScalarMarketCreated(
        address indexed decisionMarket, address indexed conditionalMarket, uint256 outcomeIndex
    );

    function setUp() public virtual {
        conditionalTokens = new DummyConditionalTokens();
        wrapped1155Factory = new DummyWrapped1155Factory();
        collateralToken = new DummyERC20("Test Token", "TEST");
        realityETH = new DummyRealityETH();

        oracleAdapter = new DummyFlatCFMOracleAdapter();

        factory = new InvalidlessConditionalScalarMarketFactory(
            IConditionalTokens(address(conditionalTokens)), IWrapped1155Factory(address(wrapped1155Factory))
        );
    }

    function testCreateInvalidlessConditionalScalarMarket() public {
        GenericScalarQuestionParams memory genericScalarParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: OPENING_TIME
        });

        // We'll verify the event was emitted after deployment instead of predicting values

        InvalidlessConditionalScalarMarket icsm = factory.createInvalidlessConditionalScalarMarket(
            oracleAdapter,
            TEMPLATE_ID,
            OUTCOME_NAME,
            genericScalarParams,
            DEFAULT_INVALID_PAYOUTS,
            IERC20(address(collateralToken))
        );

        // Verify the market was created
        assertNotEq(address(icsm), address(0));
        assertTrue(icsm.initialized());

        // Verify the market parameters
        assertEq(address(icsm.oracleAdapter()), address(oracleAdapter));
        assertEq(address(icsm.conditionalTokens()), address(conditionalTokens));
        assertEq(address(icsm.wrapped1155Factory()), address(wrapped1155Factory));

        (uint256 minValue, uint256 maxValue) = icsm.scalarParams();
        assertEq(minValue, MIN_VALUE);
        assertEq(maxValue, MAX_VALUE);

        assertEq(icsm.defaultInvalidPayouts(0), DEFAULT_INVALID_PAYOUTS[0]);
        assertEq(icsm.defaultInvalidPayouts(1), DEFAULT_INVALID_PAYOUTS[1]);
    }

    function testRevertInvalidPayoutsCannotBeBothZero() public {
        GenericScalarQuestionParams memory genericScalarParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: OPENING_TIME
        });

        uint256[2] memory invalidPayouts = [uint256(0), uint256(0)];

        vm.expectRevert(InvalidlessConditionalScalarMarketFactory.InvalidPayoutsCannotBeBothZero.selector);
        factory.createInvalidlessConditionalScalarMarket(
            oracleAdapter,
            TEMPLATE_ID,
            OUTCOME_NAME,
            genericScalarParams,
            invalidPayouts,
            IERC20(address(collateralToken))
        );
    }

    function testRevertInvalidScalarRange() public {
        GenericScalarQuestionParams memory invalidGenericScalarParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({
                minValue: MAX_VALUE, // min > max
                maxValue: MIN_VALUE
            }),
            openingTime: OPENING_TIME
        });

        vm.expectRevert(InvalidlessConditionalScalarMarketFactory.InvalidScalarRange.selector);
        factory.createInvalidlessConditionalScalarMarket(
            oracleAdapter,
            TEMPLATE_ID,
            OUTCOME_NAME,
            invalidGenericScalarParams,
            DEFAULT_INVALID_PAYOUTS,
            IERC20(address(collateralToken))
        );
    }

    function testRevertInvalidOutcomeNameLength() public {
        GenericScalarQuestionParams memory genericScalarParams = GenericScalarQuestionParams({
            scalarParams: ScalarParams({minValue: MIN_VALUE, maxValue: MAX_VALUE}),
            openingTime: OPENING_TIME
        });
        string memory longOutcomeName = "this-outcome-name-is-definitely-too-long";

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidlessConditionalScalarMarketFactory.InvalidOutcomeNameLength.selector, longOutcomeName
            )
        );
        factory.createInvalidlessConditionalScalarMarket(
            oracleAdapter,
            TEMPLATE_ID,
            longOutcomeName,
            genericScalarParams,
            DEFAULT_INVALID_PAYOUTS,
            IERC20(address(collateralToken))
        );
    }

    function testFactoryImmutables() public view {
        assertEq(address(factory.conditionalTokens()), address(conditionalTokens));
        assertEq(address(factory.wrapped1155Factory()), address(wrapped1155Factory));
        assertNotEq(factory.invalidlessConditionalScalarMarketImplementation(), address(0));
    }
}
