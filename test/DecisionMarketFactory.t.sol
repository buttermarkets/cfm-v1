// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol"; // Updated import;

import "src/butter-v1/DecisionMarketFactory.sol";
import "src/butter-v1/DecisionMarket.sol";
import "src/butter-v1/ConditionalScalarMarket.sol";
import "src/butter-v1/CFMRealityAdapter.sol";
import "src/ConditionalTokens.sol";

import "src/butter-v1/interfaces/ICFMOracleAdapter.sol";

contract CFMDecisionMarket_ConstructorSpy is CFMDecisionMarket {
    event ConstructorCalled(
        ICFMOracleAdapter adapter,
        ConditionalTokens tokens,
        CFMDecisionQuestionParams dParams,
        CFMConditionalQuestionParams cParams
    );

    constructor(
        ICFMOracleAdapter adapter,
        ConditionalTokens tokens,
        CFMDecisionQuestionParams memory dParams,
        CFMConditionalQuestionParams memory cParams
    ) CFMDecisionMarket(adapter, tokens, dParams, cParams) {
        emit ConstructorCalled(adapter, tokens, dParams, cParams);
    }
}

contract DecisionMarketFactoryTest is Test {
    DecisionMarketFactory public factory;
    CFMRealityAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    RealityETH_v3_0 public realityETH; // Instance of Reality_v3

    address owner = address(0x1);
    address user = address(0x2);

    // Shared outcomeNames array.
    string[] public outcomeNames;

    function setUp() public {
        // TODO: another test with e.g. 5
        // Initialize the shared outcomeNames array.
        outcomeNames = new string[](2);
        outcomeNames[0] = "Project X";
        outcomeNames[1] = "Project Y";

        // Deploy the ConditionalTokens contract.
        conditionalTokens = new ConditionalTokens();

        // Deploy the RealityETH_v3_0 contract.
        realityETH = new RealityETH_v3_0();

        // Deploy the RealityAdapter with Reality_v3.
        oracleAdapter =
            new CFMRealityAdapter(IRealityETH(address(realityETH)), address(0x00), 4242, 2424, 1000, 10000000000);

        // Deploy the DecisionMarketFactory with the RealityAdapter and ConditionalTokens
        factory = new DecisionMarketFactory(ICFMOracleAdapter(address(oracleAdapter)), conditionalTokens);

        // Label addresses for clarity in test outputs.
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(address(factory), "Factory");

        // Allocate ETH to owner and user for testing purposes.
        vm.deal(owner, 10 ether);
        vm.deal(user, 10 ether);
    }

    /**
     * @notice Test that the factory is deployed correctly
     */
    function testConstructorSetsAttributes() public view {
        assertEq(address(factory.oracleAdapter()), address(oracleAdapter), "Market oracle address mismatch");
        assertEq(
            address(factory.conditionalTokens()),
            address(conditionalTokens),
            "Market ConditionalTokens address mismatch"
        );
        assertEq(factory.marketCount(), 0, "Initial market count should be zero");
    }

    function testCreateMarket(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        CFMDecisionQuestionParams memory decisionQuestionParams =
            CFMDecisionQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});

        CFMConditionalQuestionParams memory conditionalQuestionParams = CFMConditionalQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            minValue: minValue,
            maxValue: maxValue,
            openingTime: scalarOpeningTime
        });

        // Create the market with the shared outcomeNames array.
        vm.prank(owner);
        factory.createMarket(decisionQuestionParams, conditionalQuestionParams);

        // TODO: test adding multiple markets. For that, atomize the test
        // contract first.
        CFMDecisionMarket createdMarket = factory.markets(0);
        // Test that the markets mapping has been updated.
        assertTrue(address(createdMarket) != address(0), "Created market address should not be zero");

        assertEq(factory.marketCount(), 1, "Market counter should be updated");

        // As we are testing deployments and we can't mock constructor calls,
        // we just check that the resulting deployed contract has the right
        // state set in basic attributes.
        assertEq(address(createdMarket.oracleAdapter()), address(oracleAdapter));
        assertEq(address(createdMarket.conditionalTokens()), address(conditionalTokens));
        assertEq(createdMarket.outcomeCount(), outcomeNames.length, "Incorrect number of conditional markets created");
        ConditionalScalarMarket csm = createdMarket.outcomes(0);
        assertEq(address(csm.oracleAdapter()), address(oracleAdapter));
        assertEq(address(csm.conditionalTokens()), address(conditionalTokens));
        assertEq(csm.minValue(), conditionalQuestionParams.minValue);
        assertEq(csm.maxValue(), conditionalQuestionParams.maxValue);
    }
}
