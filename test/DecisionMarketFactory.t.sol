// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Test.sol";
//import {RealityETH_v3_0} from "@realityeth/packages/contracts/flat/RealityETH-3.0.sol"; // Updated import;
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";

import "src/vendor/gnosis/conditional-tokens-contracts/ConditionalTokens.sol";
import "src/vendor/gnosis/1155-to-20/Wrapped1155Factory.sol";
import "src/FlatCFMFactory.sol";
import "src/FlatCFM.sol";
import "src/ConditionalScalarMarket.sol";
import "src/FlatCFMRealityAdapter.sol";
import "src/FlatCFMOracleAdapter.sol";

import "./FakeRealityETH.sol";

//contract CFMDecisionMarket_ConstructorSpy is FlatCFM {
//    event ConstructorCalled(
//        FlatCFMOracleAdapter adapter,
//        IConditionalTokens conditionalTokens,
//        FlatCFMQuestionParams cfmParams,
//        ScalarQuestionParams sParams
//    );
//
//    constructor(
//        FlatCFMOracleAdapter adapter,
//        IConditionalTokens conditionalTokens,
//        IWrapped1155Factory wrapped1155Factory,
//        IERC20 collateralToken,
//        FlatCFMQuestionParams memory dParams,
//        ScalarQuestionParams memory sParams
//    ) FlatCFM(adapter, conditionalTokens, wrapped1155Factory, collateralToken, dParams, sParams) {
//        emit ConstructorCalled(adapter, conditionalTokens, dParams, sParams);
//    }
//}

contract TestERC20 is ERC20 {
    constructor() ERC20("Test Token", "TEST") {
        _mint(msg.sender, 1000000e18);
    }
}

contract DecisionMarketFactoryTest is Test {
    FlatCFMFactory public factory;
    FlatCFMRealityAdapter public oracleAdapter;
    ConditionalTokens public conditionalTokens;
    FakeRealityETH public fakeRealityETH; // Instance of Reality_v3
    Wrapped1155Factory public wrapped1155Factory;
    IERC20 public collateralToken;

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
        fakeRealityETH = new FakeRealityETH();

        // Deploy the Wrapped1155Factory contract.
        wrapped1155Factory = new Wrapped1155Factory();
        // Deploy the RealityAdapter with Reality_v3.
        oracleAdapter = new FlatCFMRealityAdapter(
            IRealityETH(address(fakeRealityETH)), address(0x00), 4242, 2424, 1000, 10000000000
        );

        // Deploy the collateral token.
        collateralToken = new TestERC20();

        // Deploy the FlatCFMFactory with the RealityAdapter and ConditionalTokens
        factory = new FlatCFMFactory(
            oracleAdapter,
            IConditionalTokens(address(conditionalTokens)),
            IWrapped1155Factory(address(wrapped1155Factory))
        );

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
    }

    function testCreateMarket(uint32 openingTime, uint256 minValue, uint256 maxValue, uint32 scalarOpeningTime)
        public
    {
        FlatCFMQuestionParams memory decisionQuestionParams =
            FlatCFMQuestionParams({roundName: "round", outcomeNames: outcomeNames, openingTime: openingTime});

        GenericScalarQuestionParams memory conditionalQuestionParams = GenericScalarQuestionParams({
            metricName: "metric",
            startDate: "2024-01-01",
            endDate: "2025-01-01",
            scalarParams: ScalarParams({minValue: minValue, maxValue: maxValue}),
            openingTime: scalarOpeningTime
        });

        // Create the market with the shared outcomeNames array.
        vm.prank(owner);
        vm.recordLogs();
        FlatCFM createdMarket = factory.createMarket(decisionQuestionParams, conditionalQuestionParams, collateralToken);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("ConditionalMarketCreated(address,address,uint256,address)");
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

        // TODO: test adding multiple markets. For that, atomize the test
        // contract first.
        // Test that the markets mapping has been updated.
        assertTrue(address(createdMarket) != address(0), "Created market address should not be zero");

        // As we are testing deployments and we can't mock constructor calls,
        // we just check that the resulting deployed contract has the right
        // state set in basic attributes.
        assertEq(address(createdMarket.oracleAdapter()), address(oracleAdapter));
        assertEq(address(createdMarket.conditionalTokens()), address(conditionalTokens));
        assertEq(createdMarket.outcomeCount(), outcomeNames.length, "Incorrect number of conditional markets created");

        assertEq(address(firstCsm.oracleAdapter()), address(oracleAdapter));
        assertEq(address(firstCsm.conditionalTokens()), address(conditionalTokens));
        (uint256 minv, uint256 maxv) = firstCsm.scalarParams();
        assertEq(minv, conditionalQuestionParams.scalarParams.minValue);
        assertEq(maxv, conditionalQuestionParams.scalarParams.maxValue);
    }
}
