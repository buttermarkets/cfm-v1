// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./CSMJsonParser.s.sol";
import "./FlatCFMJsonParser.s.sol";

contract ApproveAllMarketTokensPermit2 is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        // Prefer reading Permit2 from config; fallback to env PERMIT2
        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address permit2;
        // vm.parseJsonAddress reverts if key missing; catch and fallback to env
        try vm.parseJsonAddress(jsonContent, ".permit2") returns (address p2) {
            permit2 = p2;
        } catch {
            permit2 = vm.envAddress("PERMIT2");
        }

        string memory json = vm.readFile(vm.envString("CSM_JSON"));
        Market[] memory markets = _parseAllMarkets(json);

        address[] memory approved = new address[](markets.length * 2);
        uint256 count = 0;

        vm.startBroadcast();
        for (uint256 i = 0; i < markets.length; i++) {
            address s = markets[i].shortToken.id;
            address l = markets[i].longToken.id;
            bool seenS = false;
            bool seenL = false;
            for (uint256 j = 0; j < count; j++) {
                if (approved[j] == s) seenS = true;
                if (approved[j] == l) seenL = true;
            }
            if (!seenS) {
                IERC20(s).approve(permit2, type(uint256).max);
                approved[count++] = s;
                console.log("Approved via Permit2:", s);
            }
            if (!seenL) {
                IERC20(l).approve(permit2, type(uint256).max);
                approved[count++] = l;
                console.log("Approved via Permit2:", l);
            }
        }
        console.log("Total unique tokens approved to Permit2:", count);
        vm.stopBroadcast();
    }
}

contract ApproveAllMarketTokensPermit2Check is CSMJsonParser, FlatCFMJsonParser {
    function run() external view {
        string memory json = vm.readFile(vm.envString("CSM_JSON"));
        Market[] memory markets = _parseAllMarkets(json);

        string memory configPath = _getJsonFilePath();
        string memory jsonContent = vm.readFile(configPath);

        address depositor = vm.envAddress("DEPOSITOR");
        address permit2;
        try vm.parseJsonAddress(jsonContent, ".permit2") returns (address p2) {
            permit2 = p2;
        } catch {
            permit2 = vm.envAddress("PERMIT2");
        }

        address[] memory seen = new address[](markets.length * 2);
        uint256 seenCount = 0;
        uint256 ok = 0;
        uint256 miss = 0;
        for (uint256 i = 0; i < markets.length; i++) {
            address s = markets[i].shortToken.id;
            address l = markets[i].longToken.id;

            bool checkedS = false;
            bool checkedL = false;
            for (uint256 j = 0; j < seenCount; j++) {
                if (seen[j] == s) checkedS = true;
                if (seen[j] == l) checkedL = true;
            }
            if (!checkedS) {
                uint256 allowanceS = IERC20(s).allowance(depositor, permit2);
                if (allowanceS > 0) ok++;
                else miss++;
                seen[seenCount++] = s;
                console.log("Short token:", s, "Allowance:", allowanceS);
            }
            if (!checkedL) {
                uint256 allowanceL = IERC20(l).allowance(depositor, permit2);
                if (allowanceL > 0) ok++;
                else miss++;
                seen[seenCount++] = l;
                console.log("Long token:", l, "Allowance:", allowanceL);
            }
        }
        console.log("Unique tokens:", seenCount);
        console.log("With allowance:", ok);
        console.log("Without allowance:", miss);
    }
}
