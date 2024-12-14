// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@realityeth/packages/contracts/development/contracts/IRealityETH.sol";

import "../src/ConditionalTokens.sol";
import "../src/FPMMDeterministicFactory.sol";
import "../src/butter-v1/interfaces/ICFMOracleAdapter.sol";
import "../src/FixedProductMarketMaker.sol";
import "../src/IConditionalTokens.sol";
import "../src/butter-v1/CFMRealityAdapter.sol";

import "../test/FakeRealityETH.sol";

// Simple ERC20 token for collateral
contract CollateralToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Collateral Token", "CLT") {
        _mint(msg.sender, initialSupply);
    }
}

contract PredictionMarketWorkflowSimulator is Script {
    ConditionalTokens public conditionalTokens;
    FPMMDeterministicFactory public fpmmFactory;
    ICFMOracleAdapter public oracleAdapter;
    FixedProductMarketMaker public marketMaker;
    CollateralToken public collateralToken;
    FakeRealityETH public fakeRealityEth;

    bytes32 public constant QUESTION_ID = bytes32("What will be the outcome?");
    uint256 public constant OUTCOME_SLOT_COUNT = 2;
    uint256 public constant INITIAL_LIQUIDITY = 1000 * 10 ** 18;

    function run() public {
        vm.startBroadcast();

        // Step 1: Deploy CollateralToken
        collateralToken = new CollateralToken(1000000 * 10 ** 18);
        assert(address(collateralToken) != address(0));

        // Step 2: Deploy ConditionalTokens
        conditionalTokens = new ConditionalTokens();
        assert(address(conditionalTokens) != address(0));

        // Step 3: Deploy FPMMDeterministicFactory
        fpmmFactory = new FPMMDeterministicFactory();
        assert(address(fpmmFactory) != address(0));

        // Step 4: Deploy FakeRealityETH
        fakeRealityEth = new FakeRealityETH();
        assert(address(fakeRealityEth) != address(0));

        // Step 5: Deploy CFM reality adapter
        oracleAdapter = new CFMRealityAdapter(
            IRealityETH(address(fakeRealityEth)), fakeRealityEth.getArbitrator(""), 42, 42, 42, 42
        );
        assert(address(oracleAdapter) != address(0));

        // Step 6: Prepare condition
        conditionalTokens.prepareCondition(address(oracleAdapter), QUESTION_ID, OUTCOME_SLOT_COUNT);
        bytes32 conditionId = CTHelpers.getConditionId(address(oracleAdapter), QUESTION_ID, OUTCOME_SLOT_COUNT);
        assert(conditionalTokens.getOutcomeSlotCount(conditionId) == OUTCOME_SLOT_COUNT);

        // Step 7: Create market maker
        uint256[] memory distributionHint = new uint256[](OUTCOME_SLOT_COUNT);
        for (uint256 i = 0; i < OUTCOME_SLOT_COUNT; i++) {
            distributionHint[i] = 1;
        }

        bytes32[] memory conditionIds = new bytes32[](1);
        conditionIds[0] = conditionId;

        // Approve the factory to spend your collateral tokens
        collateralToken.approve(address(fpmmFactory), INITIAL_LIQUIDITY);

        marketMaker = FixedProductMarketMaker(
            fpmmFactory.create2FixedProductMarketMaker(
                1,
                conditionalTokens,
                collateralToken,
                conditionIds,
                0, // fee
                INITIAL_LIQUIDITY, // Set initial funds to INITIAL_LIQUIDITY
                new uint256[](0) // empty distribution hint
            )
        );
        assert(address(marketMaker) != address(0));

        // No need for additional approval or transfer
        // The factory has already added the initial funding
        assert(marketMaker.totalSupply() > 0);

        // Step 9: Simulate trading
        uint256 tradeAmount = 100 * 10 ** 18;
        collateralToken.approve(address(marketMaker), tradeAmount);
        uint256[] memory outcomeTokenAmounts = new uint256[](OUTCOME_SLOT_COUNT);
        outcomeTokenAmounts[0] = tradeAmount;
        marketMaker.buy(outcomeTokenAmounts[0], 0, tradeAmount);
        assert(marketMaker.balanceOf(address(this)) > 0);

        // Step 10: Resolve condition
        // Mock oracle return value:
        //uint256[] memory payouts = new uint256[](OUTCOME_SLOT_COUNT);
        //payouts[0] = 1;
        //payouts[1] = 0;
        //fakeRealityEth.setResult(QUESTION_ID, bytes32(uint256(1)));
        // Resolve:
        //oracleAdapter.resolve(QUESTION_ID, 0, "What will be the outcome?", OUTCOME_SLOT_COUNT);
        assert(conditionalTokens.payoutDenominator(conditionId) > 0);

        // Step 11: Redeem winnings
        uint256 initialBalance = collateralToken.balanceOf(address(this));
        uint256[] memory indexSets = new uint256[](1);
        indexSets[0] = 1;
        conditionalTokens.redeemPositions(collateralToken, bytes32(0), conditionId, indexSets);
        assert(collateralToken.balanceOf(address(this)) > initialBalance);

        vm.stopBroadcast();
    }
}
