// SPDX-License-Identifier: GPL-3.0-or-later
// Split ICSM collateral into ERC1155 positions and wrap into ERC20s.
// Includes a check variant to verify balances before splitting.
pragma solidity ^0.8.20;

import "forge-std/src/Script.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IConditionalTokens} from "src/interfaces/IConditionalTokens.sol";
import {IWrapped1155Factory} from "src/interfaces/IWrapped1155Factory.sol";
import {InvalidlessConditionalScalarMarket} from "src/invalidless/InvalidlessConditionalScalarMarket.sol";

abstract contract SplitICSMScriptBase is Script {
    struct Config {
        address icsmAddress;
        uint256 depositAmount;
        address collateralToken;
        address conditionalTokens;
        address wrapped1155Factory;
        uint256 deadline; // optional, unused but kept for JSON compatibility
    }

    function _readConfig() internal view returns (Config memory cfg, string memory rawJson) {
        string memory path = vm.envString("LIQUIDITY_CONFIG_PATH");
        rawJson = vm.readFile(path);
        cfg = _parseConfig(rawJson);
    }

    function _parseConfig(string memory json) internal pure returns (Config memory cfg) {
        cfg.icsmAddress = vm.parseJsonAddress(json, ".icsmAddress");
        cfg.depositAmount = vm.parseJsonUint(json, ".depositAmount");
        cfg.collateralToken = vm.parseJsonAddress(json, ".collateralToken");
        cfg.conditionalTokens = vm.parseJsonAddress(json, ".conditionalTokens");
        cfg.wrapped1155Factory = vm.parseJsonAddress(json, ".wrapped1155Factory");
        try vm.parseJsonUint(json, ".deadline") returns (uint256 dl) {
            cfg.deadline = dl;
        } catch {}
    }

    function _loadWrappedData(address icsm)
        internal
        view
        returns (bytes memory shortData, bytes memory longData, IERC20 shortToken, IERC20 longToken)
    {
        uint256 unused0;
        uint256 unused1;
        (shortData, longData, unused0, unused1, shortToken, longToken) =
            InvalidlessConditionalScalarMarket(icsm).wrappedCTData();
    }

    function _loadConditionId(address icsm) internal view returns (bytes32 conditionId) {
        (, conditionId,,) = InvalidlessConditionalScalarMarket(icsm).ctParams();
    }
}

contract SplitICSM is SplitICSMScriptBase {
    function run() external {
        (Config memory cfg,) = _readConfig();

        require(cfg.icsmAddress != address(0), "Invalid ICSM address");
        require(cfg.collateralToken != address(0), "Invalid collateral token");
        require(cfg.conditionalTokens != address(0), "Invalid conditional tokens");
        require(cfg.wrapped1155Factory != address(0), "Invalid wrapped1155 factory");
        require(cfg.depositAmount > 0, "deposit=0");

        bytes32 conditionId = _loadConditionId(cfg.icsmAddress);
        (bytes memory shortData, bytes memory longData, IERC20 shortTok, IERC20 longTok) =
            _loadWrappedData(cfg.icsmAddress);

        console.log("=== Split ICSM ===");
        console.log("ICSM:", cfg.icsmAddress);
        console.log("Deposit Amount:", cfg.depositAmount);
        console.log("Owner (MY_ADDRESS):", vm.envAddress("MY_ADDRESS"));

        vm.startBroadcast();
        require(msg.sender == vm.envAddress("MY_ADDRESS"), "broadcast != MY_ADDRESS");

        IERC20(cfg.collateralToken).approve(cfg.conditionalTokens, cfg.depositAmount);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;
        IConditionalTokens(cfg.conditionalTokens).splitPosition(
            IERC20(cfg.collateralToken), bytes32(0), conditionId, partition, cfg.depositAmount
        );

        IConditionalTokens(cfg.conditionalTokens).setApprovalForAll(cfg.wrapped1155Factory, true);

        bytes32 shortColl = IConditionalTokens(cfg.conditionalTokens).getCollectionId(bytes32(0), conditionId, 1);
        bytes32 longColl = IConditionalTokens(cfg.conditionalTokens).getCollectionId(bytes32(0), conditionId, 2);
        uint256 shortId =
            IConditionalTokens(cfg.conditionalTokens).getPositionId(IERC20(cfg.collateralToken), shortColl);
        uint256 longId = IConditionalTokens(cfg.conditionalTokens).getPositionId(IERC20(cfg.collateralToken), longColl);

        IConditionalTokens(cfg.conditionalTokens).safeTransferFrom(
            vm.envAddress("MY_ADDRESS"), cfg.wrapped1155Factory, shortId, cfg.depositAmount, shortData
        );
        IConditionalTokens(cfg.conditionalTokens).safeTransferFrom(
            vm.envAddress("MY_ADDRESS"), cfg.wrapped1155Factory, longId, cfg.depositAmount, longData
        );

        vm.stopBroadcast();

        console.log(unicode"✓ Split + Wrap complete");
        console.log("Short Token:", address(shortTok));
        console.log("Long  Token:", address(longTok));
    }
}

contract SplitICSMCheck is SplitICSMScriptBase {
    function run() external view {
        (Config memory cfg,) = _readConfig();
        address account = vm.envAddress("MY_ADDRESS");

        require(account != address(0), "MY_ADDRESS unset");
        require(cfg.icsmAddress != address(0), "Invalid ICSM address");
        require(cfg.depositAmount > 0, "deposit=0");

        (,, IERC20 shortToken, IERC20 longToken) = _loadWrappedData(cfg.icsmAddress);
        require(address(shortToken) != address(0) && address(longToken) != address(0), "wrapped tokens missing");

        uint256 shortBal = shortToken.balanceOf(account);
        uint256 longBal = longToken.balanceOf(account);

        console.log("=== SplitICSMCheck ===");
        console.log("Account:", account);
        console.log("Required deposit:", cfg.depositAmount);
        console.log("Short token:", address(shortToken));
        console.log("Long  token:", address(longToken));
        console.log("Short balance:", shortBal);
        console.log("Long  balance:", longBal);

        require(shortBal >= cfg.depositAmount, "insufficient short balance");
        require(longBal >= cfg.depositAmount, "insufficient long balance");

        console.log(unicode"✓ Account already holds enough wrapped tokens");
    }
}
