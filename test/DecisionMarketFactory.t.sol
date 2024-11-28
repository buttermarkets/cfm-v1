// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import Foundry's Test library
import "forge-std-1.9.4/src/Test.sol";

// Import the contracts to be tested
import "src/butter-v1/DecisionMarketFactory.sol";
import "src/butter-v1/DecisionMarket.sol";
import "src/butter-v1/ConditionalScalarMarket.sol";
import "src/butter-v1/CFMRealityAdapter.sol";
import "src/ConditionalTokens.sol";

// Import interfaces if necessary
import "src/butter-v1/interfaces/ICFMOracleAdapter.sol";

import "./Reality_v3.sol"; // Updated import

contract DecisionMarketFactoryTest is Test {
    DecisionMarketFactory public factory;
    CFMRealityAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    RealityETH_v3_0 public realityETH; // Instance of Reality_v3

    address owner = address(0x1);
    address user = address(0x2);

    // Shared outcomeNames array
    string[] public outcomeNames;

    function setUp() public {
        // Initialize the shared outcomeNames array
        outcomeNames = new string[](2);
        outcomeNames[0] = "Project X";
        outcomeNames[1] = "Project Y";

        // Deploy the ConditionalTokens contract
        conditionalTokens = new ConditionalTokens();

        // Deploy the RealityETH_v3_0 contract
        realityETH = new RealityETH_v3_0();

        // Deploy the RealityAdapter with Reality_v3
        oracleAdapter = new CFMRealityAdapter(IRealitio(address(realityETH)), address(0x00), 1, 2, 123, 321);

        // Deploy the DecisionMarketFactory with the RealityAdapter and ConditionalTokens
        factory = new DecisionMarketFactory(ICFMOracleAdapter(address(oracleAdapter)), conditionalTokens);

        // Label addresses for clarity in test outputs
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(address(factory), "Factory");

        // Allocate ETH to owner and user for testing purposes
        vm.deal(owner, 10 ether);
        vm.deal(user, 10 ether);
    }

    /**
     * @notice Test that the factory is deployed correctly
     */
    function testFactoryDeployment() public view {
        assertEq(address(factory.oracleAdapter()), address(oracleAdapter), "Market oracle address mismatch");
        assertEq(
            address(factory.conditionalTokens()),
            address(conditionalTokens),
            "Market ConditionalTokens address mismatch"
        );
        assertEq(factory.marketCount(), 0, "Initial market count should be zero");
    }

    /**
     * @notice Test creating a new DecisionMarket via the factory
     */
    function testCreateMarket() public {
        // Prepare parameters for market creation
        CFMDecisionQuestionParams memory decisionQuestionParams =
            CFMDecisionQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: 213});

        CFMConditionalQuestionParams memory conditionalQuestionParams = CFMConditionalQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            minValue: 0,
            maxValue: 10,
            openingTime: 123
        });

        // Create the market with the shared outcomeNames array
        vm.prank(owner);
        factory.createMarket(decisionQuestionParams, conditionalQuestionParams);

        // Retrieve the created market address
        CFMDecisionMarket createdMarket = factory.markets(0);
        assertTrue(address(createdMarket) != address(0), "Created market address should not be zero");

        assertEq(createdMarket.outcomeCount(), outcomeNames.length, "Incorrect number of conditional markets created");

        for (uint256 i = 0; i < outcomeNames.length; i++) {
            ConditionalScalarMarket csm = createdMarket.outcomes(i);
            assertTrue(address(csm) != address(0), "ConditionalScalarMarket address should not be zero");
            assertEq(address(csm.oracleAdapter()), address(oracleAdapter), "CSM Oracle address mismatch");
            assertEq(
                address(csm.conditionalTokens()), address(conditionalTokens), "CSM ConditionalTokens address mismatch"
            );
        }
    }
}
