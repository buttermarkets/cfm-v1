// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "./FlatCFMJsonParser.s.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract CreateAllPairs is Script, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address factoryAddr = _parseUniswapV2Factory(jsonContent);
        string memory pairsJson = vm.envString("SHORT_LONG_PAIRS");

        address[][] memory shortLongPairs = abi.decode(vm.parseJson(pairsJson), (address[][]));

        IUniswapV2Factory factory = IUniswapV2Factory(factoryAddr);

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            address shortToken = shortLongPairs[i][0];
            address longToken = shortLongPairs[i][1];

            // ⏩ Skip if the pair already exists to avoid revert
            if (factory.getPair(shortToken, longToken) != address(0)) {
                console.log(unicode"⏭️ Skipping existing pair for tokens:", shortToken, longToken);
                continue;
            }

            vm.startBroadcast();
            address pair = factory.createPair(shortToken, longToken);
            console.log("Created pair:", pair);
            vm.stopBroadcast();
        }
    }
}
