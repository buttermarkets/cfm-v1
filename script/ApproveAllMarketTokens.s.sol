// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./CSMJsonParser.s.sol";

contract ApproveAllMarketTokens is CSMJsonParser {
    function run() external {
        address router = vm.envAddress("UNISWAP_V2_ROUTER");
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        // Parse markets
        Market[] memory csms = _parseAllMarkets(json);

        // Create arrays to track tokens we've already approved
        address[] memory approvedTokens = new address[](csms.length * 2); // Max possible tokens
        uint256 approvedCount = 0;

        vm.startBroadcast();

        for (uint256 i = 0; i < csms.length; i++) {
            // Get short and long token addresses
            address shortToken = csms[i].shortToken.id;
            address longToken = csms[i].longToken.id;

            // Check if we've already approved short token
            bool shortApproved = false;
            for (uint256 j = 0; j < approvedCount; j++) {
                if (approvedTokens[j] == shortToken) {
                    shortApproved = true;
                    break;
                }
            }

            // Approve short token if not approved yet
            if (!shortApproved) {
                approveUnlimited(shortToken, router);
                approvedTokens[approvedCount++] = shortToken;
                console.log("Approved shortToken: %s", shortToken);
            }

            // Check if we've already approved long token
            bool longApproved = false;
            for (uint256 j = 0; j < approvedCount; j++) {
                if (approvedTokens[j] == longToken) {
                    longApproved = true;
                    break;
                }
            }

            // Approve long token if not approved yet
            if (!longApproved) {
                approveUnlimited(longToken, router);
                approvedTokens[approvedCount++] = longToken;
                console.log("Approved longToken: %s", longToken);
            }
        }

        console.log("Total unique tokens approved: %d", approvedCount);

        vm.stopBroadcast();
    }

    function approveUnlimited(address token, address spender) internal {
        IERC20(token).approve(spender, type(uint256).max);
    }
}

contract ApproveAllMarketTokensSafeBatch is CSMJsonParser {
    function run() external {
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        // Parse markets
        Market[] memory csms = _parseAllMarkets(json);

        // Create arrays to track tokens we've already processed
        address[] memory processedTokens = new address[](csms.length * 2); // Max possible tokens
        uint256 processedCount = 0;

        // Create the base safe batch transfers structure
        string memory safeBatch = string.concat(
            "{\n",
            '  "version": "1.0",\n',
            '  "chainId": "130",\n',
            '  "createdAt": ',
            vm.toString(block.timestamp * 1000),
            ",\n",
            '  "meta": {\n',
            '    "name": "Unlimited Token Approvals",\n',
            '    "description": "Approve all short and long tokens for Uniswap router",\n',
            '    "txBuilderVersion": "1.18.0",\n',
            '    "createdFromSafeAddress": "',
            addressToString(vm.envAddress("DEPOSITOR")),
            '",\n',
            '    "createdFromOwnerAddress": "",\n',
            '    "checksum": "0x655f566eba929bb3f2607194e165098b8cc187eddb6d9001630207a6edaa"\n',
            "  },\n"
        );

        // Generate transactions for each token
        string memory transactions = "[";
        uint256 txCount = 0;

        for (uint256 i = 0; i < csms.length; i++) {
            // Get short and long token addresses
            address shortToken = csms[i].shortToken.id;
            address longToken = csms[i].longToken.id;

            // Check if we've already processed short token
            bool shortProcessed = false;
            for (uint256 j = 0; j < processedCount; j++) {
                if (processedTokens[j] == shortToken) {
                    shortProcessed = true;
                    break;
                }
            }

            // Generate transaction for short token if not processed yet
            if (!shortProcessed) {
                if (txCount > 0) {
                    transactions = string.concat(transactions, ",");
                }
                transactions = string.concat(
                    transactions,
                    generateApproveTransaction(shortToken, vm.envAddress("UNISWAP_V2_ROUTER"), type(uint256).max)
                );
                processedTokens[processedCount++] = shortToken;
                txCount++;
            }

            // Check if we've already processed long token
            bool longProcessed = false;
            for (uint256 j = 0; j < processedCount; j++) {
                if (processedTokens[j] == longToken) {
                    longProcessed = true;
                    break;
                }
            }

            // Generate transaction for long token if not processed yet
            if (!longProcessed) {
                if (txCount > 0) {
                    transactions = string.concat(transactions, ",");
                }
                transactions = string.concat(
                    transactions,
                    generateApproveTransaction(longToken, vm.envAddress("UNISWAP_V2_ROUTER"), type(uint256).max)
                );
                processedTokens[processedCount++] = longToken;
                txCount++;
            }
        }

        transactions = string.concat(transactions, "]");

        // Complete the safe batch json
        safeBatch = string.concat(safeBatch, '"transactions": ', transactions, "}");

        // Save to file
        vm.writeFile("./approve-all-tokens-batch.json", safeBatch);

        console.log("Generated Safe batch transfers file: approve-all-tokens-batch.json");
        console.log("Total unique tokens to approve: %d", processedCount);
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

    // Helper function to convert address to checksum string
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

contract CheckAllowances is CSMJsonParser {
    function run() external view {
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        // Parse markets
        Market[] memory csms = _parseAllMarkets(json);

        // Create arrays to track tokens we've already checked
        address[] memory checkedTokens = new address[](csms.length * 2); // Max possible tokens
        uint256 checkedCount = 0;

        console.log("Checking allowances for %d markets...", csms.length);
        console.log("Depositor: %s", vm.envAddress("DEPOSITOR"));
        console.log("Router: %s", vm.envAddress("UNISWAP_V2_ROUTER"));
        console.log("-----------------------");

        uint256 approvedCount = 0;
        uint256 notApprovedCount = 0;

        for (uint256 i = 0; i < csms.length; i++) {
            // Get short and long token addresses
            address shortToken = csms[i].shortToken.id;
            address longToken = csms[i].longToken.id;

            // Check if we've already checked short token
            bool shortChecked = false;
            for (uint256 j = 0; j < checkedCount; j++) {
                if (checkedTokens[j] == shortToken) {
                    shortChecked = true;
                    break;
                }
            }

            // Check short token allowance if not checked yet
            if (!shortChecked) {
                uint256 shortAllowance =
                    IERC20(shortToken).allowance(vm.envAddress("DEPOSITOR"), vm.envAddress("UNISWAP_V2_ROUTER"));
                console.log("ShortToken: %s", shortToken);
                console.log("Allowance: %s", shortAllowance);

                if (shortAllowance > 0) {
                    approvedCount++;
                } else {
                    notApprovedCount++;
                }

                checkedTokens[checkedCount++] = shortToken;
                console.log("-----------------------");
            }

            // Check if we've already checked long token
            bool longChecked = false;
            for (uint256 j = 0; j < checkedCount; j++) {
                if (checkedTokens[j] == longToken) {
                    longChecked = true;
                    break;
                }
            }

            // Check long token allowance if not checked yet
            if (!longChecked) {
                uint256 longAllowance =
                    IERC20(longToken).allowance(vm.envAddress("DEPOSITOR"), vm.envAddress("UNISWAP_V2_ROUTER"));
                console.log("LongToken: %s", longToken);
                console.log("Allowance: %s", longAllowance);

                if (longAllowance > 0) {
                    approvedCount++;
                } else {
                    notApprovedCount++;
                }

                checkedTokens[checkedCount++] = longToken;
                console.log("-----------------------");
            }
        }

        console.log("Summary:");
        console.log("Total unique tokens: %d", checkedCount);
        console.log("Tokens with allowance: %d", approvedCount);
        console.log("Tokens without allowance: %d", notApprovedCount);
    }
}
