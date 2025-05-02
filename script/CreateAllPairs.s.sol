// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

contract CreateAllPairs is Script {
    function run() external {
        address factoryAddr = vm.envAddress("UNISWAP_V2_FACTORY");
        string memory pairsJson = vm.envString("SHORT_LONG_PAIRS");

        address[][] memory shortLongPairs = abi.decode(vm.parseJson(pairsJson), (address[][]));

        IUniswapV2Factory factory = IUniswapV2Factory(factoryAddr);

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            address shortToken = shortLongPairs[i][0];
            address longToken = shortLongPairs[i][1];

            vm.startBroadcast();
            try factory.createPair(shortToken, longToken) returns (address pair) {
                console.log("Created pair:", pair);
            } catch Error(string memory reason) {
                if (keccak256(bytes(reason)) == keccak256(bytes("UniswapV2: PAIR_EXISTS"))) {
                    console.log(unicode"⏭️ Skipping existing pair for tokens:", shortToken, longToken);
                } else {
                    // If it's some other error, we want to revert
                    revert(reason);
                }
            }
            vm.stopBroadcast();
        }
    }
}
