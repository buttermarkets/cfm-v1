// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "./CSMJsonParser.s.sol";

// Minimal Uniswap V2 Pair interface
interface IUniswapV2Pair {
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function getReserves() external view returns (uint112, uint112, uint32);
}

contract FetchCumulativePrices is CSMJsonParser {
    function run() external {
        // Parse Markets from JSON
        string memory csmJsonPath = vm.envString("CSM_JSON");
        Market[] memory markets = _parseAllMarkets(vm.readFile(csmJsonPath));

        // Read desired blocks
        uint256 startBlock = vm.envUint("START_BLOCK");
        uint256 endBlock = vm.envUint("END_BLOCK");

        // Build top-level object
        // { "startBlock": 123, "endBlock": 456, "pairs": { ... } }
        string memory output = string.concat(
            "{", '"startBlock":', vm.toString(startBlock), ",", '"endBlock":', vm.toString(endBlock), ",", '"pairs":{'
        );

        bool firstPair = true;
        for (uint256 i = 0; i < markets.length; i++) {
            address pairAddr = markets[i].pair.id;
            if (pairAddr == address(0)) continue;

            if (!firstPair) {
                output = string.concat(output, ",");
            }
            firstPair = false;

            // Fork at START_BLOCK
            vm.createSelectFork(vm.rpcUrl("unichain-mainnet"), startBlock);
            assert(block.number == startBlock);
            IUniswapV2Pair pair = IUniswapV2Pair(pairAddr);
            (uint112 reserve0Start, uint112 reserve1Start, uint32 lastUpdateStart) = pair.getReserves();

            // Build "start" object
            string memory startData = string.concat(
                '"start":{',
                '"blockTimestamp":',
                vm.toString(block.timestamp),
                ",",
                '"blockTimestampLast":',
                vm.toString(lastUpdateStart),
                ",",
                '"reserve0":',
                vm.toString(reserve0Start),
                ",",
                '"reserve1":',
                vm.toString(reserve1Start),
                ",",
                '"price0Cumulative":',
                vm.toString(pair.price0CumulativeLast()),
                ",",
                '"price1Cumulative":',
                vm.toString(pair.price1CumulativeLast()),
                "}"
            );

            // Fork at END_BLOCK
            vm.createSelectFork(vm.rpcUrl("unichain-mainnet"), endBlock);
            assert(block.number == endBlock);
            (uint112 reserve0End, uint112 reserve1End, uint32 lastUpdateEnd) = pair.getReserves();

            // Build "end" object
            string memory endData = string.concat(
                '"end":{',
                '"blockTimestamp":',
                vm.toString(block.timestamp),
                ",",
                '"blockTimestampLast":',
                vm.toString(lastUpdateEnd),
                ",",
                '"reserve0":',
                vm.toString(reserve0End),
                ",",
                '"reserve1":',
                vm.toString(reserve1End),
                ",",
                '"price0Cumulative":',
                vm.toString(pair.price0CumulativeLast()),
                ",",
                '"price1Cumulative":',
                vm.toString(pair.price1CumulativeLast()),
                "}"
            );

            // Add pair entry: "0xABC...": { "start":..., "end":... }
            output = string.concat(output, '"', vm.toString(pairAddr), '":{', startData, ",", endData, "}");
        }

        // Close top-level braces and write to file
        output = string.concat(output, "}}");
        vm.writeFile("./cumulative-prices.json", output);
    }
}
