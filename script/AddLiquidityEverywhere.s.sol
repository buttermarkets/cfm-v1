// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./CSMJsonParser.s.sol";
import "./FlatCFMJsonParser.s.sol";

interface IUniswapV2Router {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract AddLiquidityEverywhere is Script, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address[][] memory shortLongPairs = abi.decode(vm.parseJson(vm.envString("SHORT_LONG_PAIRS")), (address[][]));
        uint256 minAmount = (_parseDepositAmount(jsonContent) * (100 - _parseSlippagePct(jsonContent))) / 100;

        // ── Check env flag ──────────────────────────────────────────
        bool forceAdd = false;
        try vm.envString("FORCE_ADD_LIQUIDITY") returns (string memory flag) {
            if (keccak256(bytes(flag)) == keccak256("true")) forceAdd = true;
        } catch { /* leave as false */ }

        vm.startBroadcast();

        for (uint256 i = 0; i < shortLongPairs.length; i++) {
            address shortTokenAddr = shortLongPairs[i][0];
            address longTokenAddr = shortLongPairs[i][1];

            // ── Skip if liquidity already exists (unless forced) ─────
            if (!forceAdd) {
                address pairAddr =
                    IUniswapV2Factory(_parseUniswapV2Factory(jsonContent)).getPair(shortTokenAddr, longTokenAddr);
                if (pairAddr != address(0) && IERC20(pairAddr).totalSupply() > 0) {
                    console.log(unicode"⏭️ Skipping liquidity (already >0) for pair:", shortTokenAddr, longTokenAddr);
                    continue;
                }
            }

            IERC20(shortTokenAddr).approve(
                address(IUniswapV2Router(_parseUniswapV2Router(jsonContent))), _parseDepositAmount(jsonContent)
            );
            IERC20(longTokenAddr).approve(
                address(IUniswapV2Router(_parseUniswapV2Router(jsonContent))), _parseDepositAmount(jsonContent)
            );

            IUniswapV2Router(_parseUniswapV2Router(jsonContent)).addLiquidity(
                shortTokenAddr,
                longTokenAddr,
                _parseDepositAmount(jsonContent),
                _parseDepositAmount(jsonContent),
                minAmount,
                minAmount,
                vm.envAddress("MY_ADDRESS"),
                block.timestamp + 600 // 10 min deadline
            );

            console.log("Liquidity added for pair index=%s short=%s long=%s", i, shortTokenAddr, longTokenAddr);
        }

        vm.stopBroadcast();
    }
}

contract AddLiquidityEverywhereCheck is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address depositor = vm.envAddress("DEPOSITOR");
        uint256 minAmount = (_parseDepositAmount(jsonContent) * (100 - _parseSlippagePct(jsonContent))) / 100;
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        Market[] memory csms = _parseAllMarkets(json);

        vm.startBroadcast();
        console.log("target min amnt:");
        console.log(minAmount);
        console.log("deadline in 60m:");
        console.log(block.timestamp + 3600);

        for (uint256 i = 0; i < csms.length; i++) {
            IERC20 short = IERC20(csms[i].shortToken.id);
            IERC20 long = IERC20(csms[i].longToken.id);
            uint256 routerAllowanceShort =
                short.allowance(depositor, address(IUniswapV2Router(_parseUniswapV2Router(jsonContent))));
            uint256 routerAllowanceLong =
                long.allowance(depositor, address(IUniswapV2Router(_parseUniswapV2Router(jsonContent))));
            IERC20 pair = IERC20(csms[i].pair.id);
            uint256 pairBalance = pair.balanceOf(depositor);

            console.log("-----------------------");

            console.log(
                (routerAllowanceShort >= _parseDepositAmount(jsonContent))
                    && (routerAllowanceLong >= _parseDepositAmount(jsonContent))
                    ? unicode"✅ allowance ok"
                    : unicode"❌ allowance not set",
                "Short // Long"
            );
            console.logUint(routerAllowanceShort);
            console.logUint(routerAllowanceLong);
            console.log("balance:");
            console.log(pairBalance);
            console.log("pair:");
            console.log(csms[i].pair.id);
        }

        vm.stopBroadcast();
    }
}

contract AddLiquidityEverywhereSafeBatchTransfers is CSMJsonParser {
    function run() external {
        uint256 amount = vm.envUint("AMOUNT");
        string memory json = vm.readFile(vm.envString("CSM_JSON"));

        Market[] memory csms = _parseAllMarkets(json);

        // Create the base safe batch transfers structure
        string memory safeBatch = generateSafeBatchBase(vm.envAddress("DEPOSITOR"));

        // Generate transactions for each market
        string memory transactions = "[";

        for (uint256 i = 0; i < csms.length; i++) {
            // Generate approve for short token
            string memory shortApprove =
                generateApproveTransaction(csms[i].shortToken.id, vm.envAddress("UNISWAP_V2_ROUTER"), amount);

            // Generate approve for long token
            string memory longApprove =
                generateApproveTransaction(csms[i].longToken.id, vm.envAddress("UNISWAP_V2_ROUTER"), amount);

            // Generate addLiquidity transaction
            string memory addLiquidity = generateAddLiquidityTransaction(
                vm.envAddress("UNISWAP_V2_ROUTER"),
                csms[i].shortToken.id,
                csms[i].longToken.id,
                amount,
                (amount * (100 - vm.envUint("SLIPPAGE_PCT"))) / 100,
                vm.envAddress("DEPOSITOR"),
                block.timestamp + 3600
            );

            // Add transactions with appropriate commas
            if (i > 0) {
                transactions = string.concat(transactions, ",");
            }

            transactions = string.concat(transactions, shortApprove, ",", longApprove, ",", addLiquidity);
        }

        transactions = string.concat(transactions, "]");

        // Complete the safe batch json
        safeBatch = string.concat(safeBatch, '"transactions": ', transactions, "}");

        // Save to file
        vm.writeFile("./addliqev-batch.json", safeBatch);

        console.log("Generated Safe batch transfers file: addliqev-batch.json");
        console.log("Includes %d markets with %d total transactions", csms.length, csms.length * 3);
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

    function generateAddLiquidityTransaction(
        address router,
        address tokenA,
        address tokenB,
        uint256 amount,
        uint256 minAmount,
        address to,
        uint256 deadline
    ) internal pure returns (string memory) {
        return string.concat(
            "{\n",
            '      "to": "',
            addressToString(router),
            '",\n',
            '      "value": "0",\n',
            '      "data": null,\n',
            '      "contractMethod": {\n',
            '        "inputs": [\n',
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "tokenA",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "tokenB",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amountADesired",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amountBDesired",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amountAMin",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "amountBMin",\n',
            '            "type": "uint256"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "address",\n',
            '            "name": "to",\n',
            '            "type": "address"\n',
            "          },\n",
            "          {\n",
            '            "internalType": "uint256",\n',
            '            "name": "deadline",\n',
            '            "type": "uint256"\n',
            "          }\n",
            "        ],\n",
            '        "name": "addLiquidity",\n',
            '        "payable": false\n',
            "      },\n",
            '      "contractInputsValues": {\n',
            '        "tokenA": "',
            addressToString(tokenA),
            '",\n',
            '        "tokenB": "',
            addressToString(tokenB),
            '",\n',
            '        "amountADesired": "',
            vm.toString(amount),
            '",\n',
            '        "amountBDesired": "',
            vm.toString(amount),
            '",\n',
            '        "amountAMin": "',
            vm.toString(minAmount),
            '",\n',
            '        "amountBMin": "',
            vm.toString(minAmount),
            '",\n',
            '        "to": "',
            addressToString(to),
            '",\n',
            '        "deadline": "',
            vm.toString(deadline),
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
