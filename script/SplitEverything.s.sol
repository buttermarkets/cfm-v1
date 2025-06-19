// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import "src/ConditionalScalarMarket.sol";
import "./CSMJsonParser.s.sol";
import "./FlatCFMJsonParser.s.sol";

contract SplitEverything is Script, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        bytes32 cfmConditionId = vm.envBytes32("CFM_CONDITION_ID");
        address collateralAddr = _parseCollateralAddress(jsonContent);
        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        address wrapped1155FactoryAddr = vm.envAddress("WRAPPED_1155_FACTORY");
        uint256 depositAmount = _parseDepositAmount(jsonContent);
        address[] memory csmList = abi.decode(vm.parseJson(vm.envString("CSM_LIST")), (address[]));
        bool skipApprovals = vm.envOr("SKIP_APPROVALS", false);

        IERC20 collateral = IERC20(collateralAddr);
        IConditionalTokens conditionalTokens = IConditionalTokens(conditionalTokensAddr);
        uint256 outcomeCount = csmList.length + 1;
        uint256[] memory partition = new uint256[](outcomeCount);
        for (uint256 i = 0; i < outcomeCount; i++) {
            partition[i] = 1 << i;
        }

        console.log("outcomeCount %s", outcomeCount);
        console.log("skipApprovals %s", skipApprovals);

        vm.startBroadcast();

        collateral.approve(conditionalTokensAddr, depositAmount);
        conditionalTokens.splitPosition(collateral, bytes32(0), cfmConditionId, partition, depositAmount);

        for (uint256 i = 0; i < csmList.length; i++) {
            ConditionalScalarMarket csm = ConditionalScalarMarket(csmList[i]);
            
            // Get the market parameters
            (, bytes32 conditionId, bytes32 parentCollectionId,) = csm.ctParams();
            (
                bytes memory shortData,
                bytes memory longData,
                bytes memory invalidData,
                uint256 shortPositionId,
                uint256 longPositionId,
                uint256 invalidPositionId,
                ,
                ,
            ) = csm.wrappedCTData();

            // Split the position for this market
            uint256[] memory scalarPartition = new uint256[](3);
            scalarPartition[0] = 1; // short
            scalarPartition[1] = 2; // long
            scalarPartition[2] = 4; // invalid
            
            conditionalTokens.splitPosition(
                collateral, parentCollectionId, conditionId, scalarPartition, depositAmount
            );

            // Transfer to wrapped1155Factory to get ERC20s
            conditionalTokens.safeTransferFrom(
                msg.sender, wrapped1155FactoryAddr, shortPositionId, depositAmount, shortData
            );
            conditionalTokens.safeTransferFrom(
                msg.sender, wrapped1155FactoryAddr, longPositionId, depositAmount, longData
            );
            conditionalTokens.safeTransferFrom(
                msg.sender, wrapped1155FactoryAddr, invalidPositionId, depositAmount, invalidData
            );
        }

        vm.stopBroadcast();
    }
}

contract SplitEverythingCheck is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        address collateralAddr = _parseCollateralAddress(jsonContent);
        uint256 depositAmount = _parseDepositAmount(jsonContent);
        address depositor = vm.envAddress("DEPOSITOR");

        IConditionalTokens conditionalTokens = IConditionalTokens(conditionalTokensAddr);
        IERC20 collateral = IERC20(collateralAddr);

        Market[] memory csms = _parseAllMarkets(vm.readFile(vm.envString("CSM_JSON")));
        uint256 outcomeCount = csms.length + 1;
        uint256[] memory partition = _generatePartitionArray(outcomeCount);

        {
            uint256 ctAllowance = collateral.allowance(depositor, conditionalTokensAddr);

            vm.startBroadcast();

            console.log("=============================");
            console.log(
                (ctAllowance >= depositAmount) ? unicode"✅ CT allowance ok" : unicode"❌ CT allowance not set",
                "ConditionalTokens allowance:"
            );
            console.log(ctAllowance);
        }
        {
            uint256 erc1155BalanceInvalid = conditionalTokens.balanceOf(
                depositor,
                conditionalTokens.getPositionId(
                    collateral,
                    conditionalTokens.getCollectionId(
                        bytes32(0), vm.envBytes32("CFM_CONDITION_ID"), partition[outcomeCount - 1]
                    )
                )
            );
            console.log("Invalid ERC1155 balance:");
            console.log(erc1155BalanceInvalid);
        }

        for (uint256 i = 0; i < csms.length; i++) {
            console.log("--------------------------");
            uint256 erc1155Balance = conditionalTokens.balanceOf(
                depositor,
                conditionalTokens.getPositionId(
                    collateral,
                    conditionalTokens.getCollectionId(bytes32(0), vm.envBytes32("CFM_CONDITION_ID"), partition[i])
                )
            );
            console.log(
                (erc1155Balance >= depositAmount) ? unicode"✅ splitPosition done" : unicode"❌ splitPosition not done",
                "Position balance:"
            );
            console.log(erc1155Balance);

            IERC20 short = IERC20(csms[i].shortToken.id);
            IERC20 long = IERC20(csms[i].longToken.id);
            IERC20 invalid = IERC20(csms[i].invalidToken.id);

            console.log(csms[i].id);
            uint256 sbal = short.balanceOf(depositor);
            uint256 lbal = long.balanceOf(depositor);
            uint256 ibal = invalid.balanceOf(depositor);
            console.log((sbal >= depositAmount) && (lbal >= depositAmount) ? unicode"✅" : unicode"❌", "Short // Long // Invalid:");
            console.logUint(sbal);
            console.logUint(lbal);
            console.logUint(ibal);
        }

        vm.stopBroadcast();
    }
}

contract SplitEverythingSafeBatchTransfers is CSMJsonParser {
    function run() external {
        bytes32 cfmConditionId = vm.envBytes32("CFM_CONDITION_ID");
        address collateralAddr = vm.envAddress("COLLATERAL_TOKEN");
        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        address wrapped1155FactoryAddr = vm.envAddress("WRAPPED_1155_FACTORY");
        uint256 amount = vm.envUint("AMOUNT");
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        console.log("Skip approvals: %s", vm.envOr("SKIP_APPROVALS", false));

        Market[] memory csms = _parseAllMarkets(json);

        // Create the base safe batch transfers structure
        string memory safeBatch = generateSafeBatchBase(vm.envAddress("DEPOSITOR"));

        // Generate transactions for each market
        string memory transactions = "[";

        // First approve collateral tokens for the initial split
        string memory collateralApprove = generateApproveTransaction(collateralAddr, conditionalTokensAddr, amount);
        transactions = string.concat(transactions, collateralApprove);

        // Initial split position for parent conditionals
        uint256 outcomeCount = csms.length + 1;
        string memory partition = _generatePartitionArrayString(outcomeCount);

        console.log("outcomeCount %s", outcomeCount);

        string memory splitPosition = generateSplitPositionTransaction(
            conditionalTokensAddr, collateralAddr, bytes32(0), cfmConditionId, partition, amount
        );

        transactions = string.concat(transactions, ",", splitPosition);

        // For each CSM, split and transfer to wrapped1155Factory
        for (uint256 i = 0; i < csms.length; i++) {
            ConditionalScalarMarket csm = ConditionalScalarMarket(csms[i].id);
            
            // Get the market parameters
            (, bytes32 conditionId, bytes32 parentCollectionId,) = csm.ctParams();
            (
                bytes memory shortData,
                bytes memory longData,
                bytes memory invalidData,
                uint256 shortPositionId,
                uint256 longPositionId,
                uint256 invalidPositionId,
                ,
                ,
            ) = csm.wrappedCTData();

            // Generate split transaction for the CSM
            string memory split = generateSplitPositionTransaction(
                conditionalTokensAddr, collateralAddr, parentCollectionId, conditionId, "[1,2,4]", amount
            );

            // Generate transfer transactions
            string memory transferShort = generateTransferTransaction(
                conditionalTokensAddr, wrapped1155FactoryAddr, shortPositionId, amount, shortData
            );
            string memory transferLong = generateTransferTransaction(
                conditionalTokensAddr, wrapped1155FactoryAddr, longPositionId, amount, longData
            );
            string memory transferInvalid = generateTransferTransaction(
                conditionalTokensAddr, wrapped1155FactoryAddr, invalidPositionId, amount, invalidData
            );

            // Add transactions
            transactions = string.concat(transactions, ",", split, ",", transferShort, ",", transferLong, ",", transferInvalid);
        }

        transactions = string.concat(transactions, "]");

        // Complete the safe batch json
        safeBatch = string.concat(safeBatch, '"transactions": ', transactions, "}");

        // Save to file
        vm.writeFile("./spliteverything-batch.json", safeBatch);

        console.log("Generated Safe batch transfers file: spliteverything-batch.json");
        uint256 totalTransactions = csms.length * 4 + 2; // 4 per market (split + 3 transfers) + collateral approval + initial split

        console.log("Includes %d markets with %d total transactions", csms.length, totalTransactions);
    }

    function generateSafeBatchBase(address safeAddress) internal view returns (string memory) {
        return string.concat(
            "{\n",
            '  "version": "1.0",\n',
            '  "chainId": "130",\n',
            '  "createdAt": ',
            vm.toString(block.timestamp * 1000),
            ",\n",
            '  "meta": {\n',
            '    "name": "Transactions Batch",\n',
            '    "description": "",\n',
            '    "txBuilderVersion": "1.18.0",\n',
            '    "createdFromSafeAddress": "',
            addressToString(safeAddress),
            '",\n',
            '    "createdFromOwnerAddress": "",\n',
            '    "checksum": "0x655f566eba929bb3f2607194e165098b8cc187eddb6d9001630207a6edaa"\n',
            "  },\n"
        );
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

    function generateSplitPositionTransaction(
        address conditionalTokensAddr,
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        string memory partition,
        uint256 amount
    ) internal pure returns (string memory) {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(conditionalTokensAddr),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "collateralToken",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "bytes32",\n',
            '            "name": "parentCollectionId",\n',
            '            "type": "bytes32"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "bytes32",\n',
            '            "name": "conditionId",\n',
            '            "type": "bytes32"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256[]",\n',
            '            "name": "partition",\n',
            '            "type": "uint256[]"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amount",\n',
            '            "type": "uint256"\n',
            "          }\n",
            "        ],\n",
            '        "name": "splitPosition",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "collateralToken": "',
            addressToString(collateralToken),
            '",\n',
            '        "parentCollectionId": "',
            bytes32ToString(parentCollectionId),
            '",\n',
            '        "conditionId": "',
            bytes32ToString(conditionId),
            '",\n',
            '        "partition": ',
            partition,
            ",\n",
            '        "amount": "',
            vm.toString(amount),
            '"\n',
            "      }\n",
            "    }"
        );
    }

    function generateSetApprovalForAllTransaction(address conditionalTokensAddr, address operator, bool approved)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(conditionalTokensAddr),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "operator",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "bool",\n',
            '            "name": "approved",\n',
            '            "type": "bool"\n',
            "          }\n",
            "        ],\n",
            '        "name": "setApprovalForAll",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "operator": "',
            addressToString(operator),
            '",\n',
            '        "approved": "',
            approved ? "true" : "false",
            '"\n',
            "      }\n",
            "    }"
        );
    }

    function generateCSMSplitTransaction(address csm, uint256 amount) internal pure returns (string memory) {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(csm),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amount",\n',
            '            "type": "uint256"\n',
            "          }\n",
            "        ],\n",
            '        "name": "split",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "amount": "',
            vm.toString(amount),
            '"\n',
            "      }\n",
            "    }"
        );
    }

    function generateTransferTransaction(address conditionalTokensAddr, address to, uint256 tokenId, uint256 amount, bytes memory data)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(conditionalTokensAddr),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "to",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "tokenId",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amount",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "bytes",\n',
            '            "name": "data",\n',
            '            "type": "bytes"\n',
            "          }\n",
            "        ],\n",
            '        "name": "safeTransferFrom",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "to": "',
            addressToString(to),
            '",\n',
            '        "tokenId": "',
            vm.toString(tokenId),
            '",\n',
            '        "amount": "',
            vm.toString(amount),
            '",\n',
            '        "data": "',
            bytesToHex(data),
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

    // Helper function to convert bytes32 to hex string
    function bytes32ToString(bytes32 value) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(66);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 32; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i] & 0x0f)];
        }

        return string(str);
    }

    // Helper function to convert bytes to hex string
    function bytesToHex(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory hexData = new bytes(data.length * 2);
        for (uint256 i = 0; i < data.length; i++) {
            hexData[i * 2] = alphabet[uint8(data[i]) >> 4];
            hexData[i * 2 + 1] = alphabet[uint8(data[i]) & 0xf];
        }
        return string(hexData);
    }
}
