// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import "src/ConditionalScalarMarket.sol";

contract SplitEverything is Script {
    function run() external {
        bytes32 cfmConditionId = vm.envBytes32("CFM_CONDITION_ID");
        address collateralAddr = vm.envAddress("COLLATERAL_TOKEN");
        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        uint256 amount = vm.envUint("AMOUNT");
        address[] memory csmList = abi.decode(vm.parseJson(vm.envString("CSM_LIST")), (address[]));

        IERC20 collateral = IERC20(collateralAddr);
        IConditionalTokens conditionalTokens = IConditionalTokens(conditionalTokensAddr);
        uint256 outcomeCount = csmList.length + 1;
        uint256[] memory partition = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;
        }

        console.log("outcomeCount %s", outcomeCount);

        vm.startBroadcast();

        collateral.approve(conditionalTokensAddr, amount);
        conditionalTokens.splitPosition(collateral, bytes32(0), cfmConditionId, partition, amount);

        for (uint256 i = 0; i < csmList.length; i++) {
            ConditionalScalarMarket csm = ConditionalScalarMarket(csmList[i]);
            conditionalTokens.setApprovalForAll(address(csm), true);
            csm.split(amount);
        }

        vm.stopBroadcast();
    }
}
