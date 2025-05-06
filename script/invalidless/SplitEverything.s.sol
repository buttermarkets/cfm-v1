// SPDX-License-Identifier: GPL-3.0-or-later
/* solhint-disable no-console */
pragma solidity 0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import "src/invalidless/InvalidlessConditionalScalarMarket.sol";
import "../CSMJsonParser.s.sol";
import "../FlatCFMJsonParser.s.sol";

contract SplitEverythingInvalidless is Script, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        // ── immutable context ────────────────────────────────────────
        bytes32 cfmConditionId = vm.envBytes32("CFM_CONDITION_ID");
        uint256 amount = vm.envUint("AMOUNT");
        bool skipApprovals = vm.envOr("SKIP_APPROVALS", false);

        IERC20 collateral = IERC20(_parseCollateralAddress(jsonContent));
        IConditionalTokens conditionalTok = IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS"));
        address[] memory icsmList = abi.decode(vm.parseJson(vm.envString("CSM_LIST")), (address[]));

        // ── parent split (keeps locals low) ───────────────────────────
        _splitParent(collateral, conditionalTok, cfmConditionId, amount, icsmList.length);

        // ── per-market work moved to helper to free the caller's stack ─
        for (uint256 i; i < icsmList.length; ++i) {
            _splitICSM(conditionalTok, InvalidlessConditionalScalarMarket(icsmList[i]), amount, skipApprovals);
        }
    }

    function _splitParent(IERC20 collateral, IConditionalTokens ct, bytes32 condId, uint256 amt, uint256 outcomeCount)
        internal
    {
        uint256[] memory partition = new uint256[](outcomeCount + 1);
        for (uint256 i; i < outcomeCount + 1; ++i) {
            partition[i] = 1 << i;
        }

        collateral.approve(address(ct), amt);
        ct.splitPosition(collateral, bytes32(0), condId, partition, amt);
    }

    function _splitICSM(IConditionalTokens ct, InvalidlessConditionalScalarMarket icsm, uint256 amt, bool skipApprovals)
        internal
    {
        if (!skipApprovals) ct.setApprovalForAll(address(icsm.wrapped1155Factory()), true);

        (, bytes32 condId, bytes32 parentCollId, IERC20 collToken) = icsm.ctParams();
        (,, uint256 shortId, uint256 longId,,) = icsm.wrappedCTData();

        uint256[] memory payouts = new uint256[](2);
        payouts[0] = uint256(1);
        payouts[1] = uint256(2);
        ct.splitPosition(collToken, parentCollId, condId, payouts, amt);

        ct.safeTransferFrom(address(this), address(icsm.wrapped1155Factory()), shortId, amt, "");
        ct.safeTransferFrom(address(this), address(icsm.wrapped1155Factory()), longId, amt, "");
    }
}

contract SplitEverythingInvalidlessCheck is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        address collateralAddr = _parseCollateralAddress(jsonContent);
        uint256 amount = vm.envUint("AMOUNT");
        address depositor = vm.envAddress("DEPOSITOR");

        IConditionalTokens conditionalTokens = IConditionalTokens(conditionalTokensAddr);
        IERC20 collateral = IERC20(collateralAddr);

        Market[] memory icsms = _parseAllMarkets(vm.readFile(vm.envString("CSM_JSON")));
        uint256 outcomeCount = icsms.length + 1;
        uint256[] memory partition = _generatePartitionArray(outcomeCount);

        {
            uint256 ctAllowance = collateral.allowance(depositor, conditionalTokensAddr);

            vm.startBroadcast();

            console.log("=============================");
            console.log(
                (ctAllowance >= amount) ? unicode"✅ CT allowance ok" : unicode"❌ CT allowance not set",
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

        for (uint256 i = 0; i < icsms.length; i++) {
            console.log("--------------------------");
            uint256 erc1155Balance = conditionalTokens.balanceOf(
                depositor,
                conditionalTokens.getPositionId(
                    collateral,
                    conditionalTokens.getCollectionId(bytes32(0), vm.envBytes32("CFM_CONDITION_ID"), partition[i])
                )
            );
            console.log(
                (erc1155Balance >= amount) ? unicode"✅ splitPosition done" : unicode"❌ splitPosition not done",
                "Position balance:"
            );
            console.log(erc1155Balance);

            IERC20 short = IERC20(icsms[i].shortToken.id);
            IERC20 long = IERC20(icsms[i].longToken.id);

            console.log(icsms[i].id);
            InvalidlessConditionalScalarMarket icsm = InvalidlessConditionalScalarMarket(icsms[i].id);
            console.log(
                conditionalTokens.isApprovedForAll(depositor, address(icsm.wrapped1155Factory()))
                    ? unicode"✅ is approved for all"
                    : unicode"❌ NOT APPROVED FOR ALL"
            );
            uint256 sbal = short.balanceOf(depositor);
            uint256 lbal = long.balanceOf(depositor);
            console.log((sbal >= amount) && (lbal >= amount) ? unicode"✅" : unicode"❌", "Short // Long:");
            console.logUint(sbal);
            console.logUint(lbal);
        }

        vm.stopBroadcast();
    }
}

contract SplitEverythingInvalidlessSafeBatchTransfers is CSMJsonParser, FlatCFMJsonParser {
    string private batchBase;
    string private currentTransactions;

    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        bytes32 cfmConditionId = vm.envBytes32("CFM_CONDITION_ID");
        address collateralAddr = _parseCollateralAddress(jsonContent);
        address conditionalTokensAddr = vm.envAddress("CONDITIONAL_TOKENS");
        uint256 amount = vm.envUint("AMOUNT");
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        console.log("Skip approvals: %s", vm.envOr("SKIP_APPROVALS", false));

        Market[] memory icsms = _parseAllMarkets(json);

        // Initialize base structure
        batchBase = generateSafeBatchBase(vm.envAddress("DEPOSITOR"));
        currentTransactions = "[";

        // Generate collateral approval
        _appendTransaction(generateApproveTransaction(collateralAddr, conditionalTokensAddr, amount));

        // Generate initial split position
        uint256 outcomeCount = icsms.length + 1;
        string memory partition = _generatePartitionArrayString(outcomeCount);
        _appendTransaction(
            generateSplitPositionTransaction(
                conditionalTokensAddr, collateralAddr, bytes32(0), cfmConditionId, partition, amount
            )
        );

        // Generate transactions for each market
        _generateMarketTransactions(icsms, conditionalTokensAddr, amount);

        // Complete the transactions array and safe batch json
        currentTransactions = string.concat(currentTransactions, "]");
        string memory safeBatch = string.concat(batchBase, '"transactions": ', currentTransactions, "}");

        // Save to file
        vm.writeFile("./spliteverything-invalidless-batch.json", safeBatch);

        _logSummary(icsms.length);
    }

    function _appendTransaction(string memory transaction) private {
        if (bytes(currentTransactions).length > 1) {
            // If not first transaction
            currentTransactions = string.concat(currentTransactions, ",");
        }
        currentTransactions = string.concat(currentTransactions, transaction);
    }

    function _generateMarketTransactions(Market[] memory icsms, address conditionalTokensAddr, uint256 amount)
        private
    {
        for (uint256 i = 0; i < icsms.length; i++) {
            InvalidlessConditionalScalarMarket icsm = InvalidlessConditionalScalarMarket(icsms[i].id);

            // Get market parameters
            (bytes32 conditionId, bytes32 parentCollectionId) = _getMarketParams(icsm);
            (uint256 shortPositionId, uint256 longPositionId) = _getPositionIds(icsm);

            // Get collateral token
            (,,, IERC20 collateralToken) = icsm.ctParams();

            // Generate approval if needed
            if (!vm.envOr("SKIP_APPROVALS", false)) {
                _appendTransaction(
                    generateSetApprovalForAllTransaction(
                        conditionalTokensAddr, address(icsm.wrapped1155Factory()), true
                    )
                );
            }

            // Generate split transaction
            _appendTransaction(
                generateSplitPositionTransaction(
                    conditionalTokensAddr, address(collateralToken), parentCollectionId, conditionId, "[1,2]", amount
                )
            );

            // Generate transfer transactions
            _appendTransaction(
                generateTransferTransaction(
                    conditionalTokensAddr, address(icsm.wrapped1155Factory()), shortPositionId, amount
                )
            );
            _appendTransaction(
                generateTransferTransaction(
                    conditionalTokensAddr, address(icsm.wrapped1155Factory()), longPositionId, amount
                )
            );
        }
    }

    function _getMarketParams(InvalidlessConditionalScalarMarket icsm) private view returns (bytes32, bytes32) {
        (, bytes32 conditionId, bytes32 parentCollectionId,) = icsm.ctParams();
        return (conditionId, parentCollectionId);
    }

    function _getPositionIds(InvalidlessConditionalScalarMarket icsm) private view returns (uint256, uint256) {
        (,, uint256 shortPositionId, uint256 longPositionId,,) = icsm.wrappedCTData();
        return (shortPositionId, longPositionId);
    }

    function _logSummary(uint256 marketCount) private view {
        console.log("Generated Safe batch transfers file: spliteverything-invalidless-batch.json");
        uint256 totalTransactions = vm.envOr("SKIP_APPROVALS", false)
            // 3 per market (split + 2 transfers) + collateral approval + initial split
            ? marketCount * 3 + 2
            // 4 per market (approval + split + 2 transfers) + collateral approval + initial split
            : marketCount * 4 + 2;

        console.log("Includes %d markets with %d total transactions", marketCount, totalTransactions);
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

    function generateTransferTransaction(address conditionalTokensAddr, address to, uint256 id, uint256 amount)
        internal
        view
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
            '            "name": "from",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "to",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "id",\n',
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
            '        "from": "',
            addressToString(vm.envAddress("DEPOSITOR")),
            '",\n',
            '        "to": "',
            addressToString(to),
            '",\n',
            '        "id": "',
            vm.toString(id),
            '",\n',
            '        "amount": "',
            vm.toString(amount),
            '",\n',
            '        "data": "0x"\n',
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
}
