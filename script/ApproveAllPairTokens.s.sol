// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./CSMJsonParser.s.sol";
import "./FlatCFMJsonParser.s.sol";

contract ApproveAllPairTokens is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address router = _parseUniswapV2Router(jsonContent);
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        Market[] memory markets = _parseAllMarkets(json);

        // Track which pair tokens we've already approved
        address[] memory approvedPairs = new address[](markets.length);
        uint256 approvedCount = 0;

        vm.startBroadcast();

        for (uint256 i = 0; i < markets.length; i++) {
            address pair = markets[i].pair.id;

            // Check if already approved
            bool alreadyApproved = false;
            for (uint256 j = 0; j < approvedCount; j++) {
                if (approvedPairs[j] == pair) {
                    alreadyApproved = true;
                    break;
                }
            }

            if (!alreadyApproved) {
                IERC20(pair).approve(router, type(uint256).max);
                approvedPairs[approvedCount++] = pair;
                console.log("Approved pair token: %s", pair);
            }
        }

        console.log("Total unique pair tokens approved: %d", approvedCount);
    }
}

contract ApproveAllPairTokensCheck is CSMJsonParser, FlatCFMJsonParser {
    function run() external view {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        string memory json = vm.readFile(vm.envString("CSM_JSON"));
        Market[] memory markets = _parseAllMarkets(json);

        address depositor = vm.envAddress("DEPOSITOR");
        address router = _parseUniswapV2Router(jsonContent);

        address[] memory checkedPairs = new address[](markets.length);
        uint256 checkedCount = 0;

        console.log("Checking pair allowances for %d markets...", markets.length);
        console.log("Depositor: %s", depositor);
        console.log("Router: %s", router);
        console.log("-----------------------");

        uint256 approvedCount = 0;
        uint256 notApprovedCount = 0;

        for (uint256 i = 0; i < markets.length; i++) {
            address pair = markets[i].pair.id;

            bool alreadyChecked = false;
            for (uint256 j = 0; j < checkedCount; j++) {
                if (checkedPairs[j] == pair) {
                    alreadyChecked = true;
                    break;
                }
            }

            if (!alreadyChecked) {
                uint256 allowance = IERC20(pair).allowance(depositor, router);
                console.log("Pair: %s", pair);
                console.log("Allowance: %s", allowance);

                if (allowance > 0) {
                    approvedCount++;
                } else {
                    notApprovedCount++;
                }

                checkedPairs[checkedCount++] = pair;
                console.log("-----------------------");
            }
        }

        console.log("Summary:");
        console.log("Total unique pairs: %d", checkedCount);
        console.log("Pairs with allowance: %d", approvedCount);
        console.log("Pairs without allowance: %d", notApprovedCount);
    }
}

contract ApproveAllPairTokensSafeBatch is CSMJsonParser {
    function run() external {
        string memory json = vm.readFile(vm.envString("CSM_JSON"));
        Market[] memory markets = _parseAllMarkets(json);

        // Track which pair tokens we've processed
        address[] memory processedPairs = new address[](markets.length);
        uint256 processedCount = 0;

        // Build the base safe batch structure
        string memory safeBatch = string.concat(
            "{\n",
            '  "version": "1.0",\n',
            '  "chainId": "130",\n',
            '  "createdAt": ',
            vm.toString(block.timestamp * 1000),
            ",\n",
            '  "meta": {\n',
            '    "name": "Unlimited Pair Approvals",\n',
            '    "description": "Approve all pair tokens for Uniswap router",\n',
            '    "txBuilderVersion": "1.18.0",\n',
            '    "createdFromSafeAddress": "',
            addressToString(vm.envAddress("DEPOSITOR")),
            '",\n',
            '    "createdFromOwnerAddress": "",\n',
            '    "checksum": "0x655f566eba929bb3f2607194e165098b8cc187eddb6d9001630207a6edaa"\n',
            "  },\n"
        );

        // Generate transactions for each unique pair
        string memory transactions = "[";
        uint256 txCount = 0;

        for (uint256 i = 0; i < markets.length; i++) {
            address pair = markets[i].pair.id;

            bool alreadyProcessed = false;
            for (uint256 j = 0; j < processedCount; j++) {
                if (processedPairs[j] == pair) {
                    alreadyProcessed = true;
                    break;
                }
            }

            if (!alreadyProcessed) {
                if (txCount > 0) {
                    transactions = string.concat(transactions, ",");
                }
                transactions = string.concat(
                    transactions,
                    generateApproveTransaction(pair, vm.envAddress("UNISWAP_V2_ROUTER"), type(uint256).max)
                );
                processedPairs[processedCount++] = pair;
                txCount++;
            }
        }

        transactions = string.concat(transactions, "]");

        // Complete and write the JSON
        safeBatch = string.concat(safeBatch, '"transactions": ', transactions, "}");
        vm.writeFile("./approve-all-pair-tokens-batch.json", safeBatch);

        console.log("Generated Safe batch file: approve-all-pair-tokens-batch.json");
        console.log("Total unique pairs to approve: %d", processedCount);
    }

    function generateApproveTransaction(address token, address spender, uint256 value)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(token),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "name": "spender",\n',
            '            "type": "address",\n',
            '            "internalType": "address"\n',
            "          },\n",
            "          {\n",
            '            "name": "value",\n',
            '            "type": "uint256",\n',
            '            "internalType": "uint256"\n',
            "          }\n",
            "        ],\n",
            '        "name": "approve",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "spender": "',
            addressToString(spender),
            '",\n',
            '        "value": "',
            vm.toString(value),
            '"\n',
            "      }\n",
            "    }"
        );
    }

    function addressToString(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }
}
