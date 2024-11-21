// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Import Foundry's Test library
import "forge-std-1.9.4/src/Test.sol";

// Import the contracts to be tested
import "src/butter-v1/DecisionMarketFactory.sol";
import "src/butter-v1/DecisionMarket.sol";
import "src/butter-v1/ConditionalScalarMarket.sol";
import "src/butter-v1/OracleAdapter.sol";
import "src/ConditionalTokens.sol";

// Import interfaces if necessary
import "src/butter-v1/interfaces/IOracle.sol";
import "src/butter-v1/interfaces/IMarket.sol";

import "./Reality_v3.sol"; // Updated import

contract DecisionMarketFactoryTest is Test {
    DecisionMarketFactory public factory;
    OracleAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    RealityETH_v3_0 public realityETH; // Instance of Reality_v3

    address owner = address(0x1);
    address user = address(0x2);

    // Shared outcomes array
    string[] public outcomes;

    function setUp() public {
        // Initialize the shared outcomes array
        outcomes = new string[](2);
        outcomes[0] = "Project X";
        outcomes[1] = "Project Y";

        // Deploy the ConditionalTokens contract
        conditionalTokens = new ConditionalTokens();

        // Deploy the RealityETH_v3_0 contract
        realityETH = new RealityETH_v3_0();

        // Deploy the OracleAdapter with Reality_v3
        oracleAdapter = new OracleAdapter(IRealitio(address(realityETH)));

        // Deploy the DecisionMarketFactory with the OracleAdapter and ConditionalTokens
        factory = new DecisionMarketFactory(IOracle(address(oracleAdapter)), conditionalTokens);

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
    function testFactoryDeployment() public {
        assertEq(address(factory.oracle()), address(oracleAdapter), "Market oracle address mismatch");
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
        MultiCategoricalQuestion memory multiCatQuestion =
            MultiCategoricalQuestion({text: "Which project will be funded?", outcomes: outcomes});

        ScalarQuestion memory scalarQuestion =
            ScalarQuestion({text: "What will be the rate of success of %s?", lowerBound: 0, upperBound: 100});

        // Create the market with the shared outcomes array
        vm.prank(owner);
        factory.createMarket(multiCatQuestion, scalarQuestion);

        // Retrieve the created market address
        DecisionMarket createdMarket = factory.markets(0);
        assertTrue(address(createdMarket) != address(0), "Created market address should not be zero");

        // Verify that ConditionalScalarMarkets are created within DecisionMarket
        assertEq(createdMarket.outcomeCount(), outcomes.length, "Incorrect number of ConditionalScalarMarkets created");

        for (uint256 i = 0; i < outcomes.length; i++) {
            ConditionalScalarMarket csm = createdMarket.outcomes(i);
            assertTrue(address(csm) != address(0), "ConditionalScalarMarket address should not be zero");
            assertEq(address(csm.oracle()), address(oracleAdapter), "CSM Oracle address mismatch");
            assertEq(
                address(csm.conditionalTokens()), address(conditionalTokens), "CSM ConditionalTokens address mismatch"
            );
        }
    }
}
