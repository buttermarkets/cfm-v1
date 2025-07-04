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
        address[] memory csmList = abi.decode(vm.parseJson(vm.envString("CSM_LIST")), (address[]));

        uint256[] memory partition = new uint256[](csmList.length + 1);
        for (uint256 i = 0; i < csmList.length + 1; i++) {
            partition[i] = 1 << i;
        }

        console.log("outcomeCount %s", csmList.length + 1);

        vm.startBroadcast();

        IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))).approve(
            vm.envAddress("CONDITIONAL_TOKENS"), _parseDepositAmount(vm.readFile(_getJsonFilePath()))
        );
        IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).splitPosition(
            IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))),
            bytes32(0),
            vm.envBytes32("CFM_CONDITION_ID"),
            partition,
            _parseDepositAmount(vm.readFile(_getJsonFilePath()))
        );

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

            IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).splitPosition(
                IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))),
                parentCollectionId,
                conditionId,
                scalarPartition,
                _parseDepositAmount(vm.readFile(_getJsonFilePath()))
            );

            // Transfer to wrapped1155Factory to get ERC20s
            IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).safeTransferFrom(
                msg.sender,
                vm.envAddress("WRAPPED_1155_FACTORY"),
                shortPositionId,
                _parseDepositAmount(vm.readFile(_getJsonFilePath())),
                shortData
            );
            IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).safeTransferFrom(
                msg.sender,
                vm.envAddress("WRAPPED_1155_FACTORY"),
                longPositionId,
                _parseDepositAmount(vm.readFile(_getJsonFilePath())),
                longData
            );
            IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).safeTransferFrom(
                msg.sender,
                vm.envAddress("WRAPPED_1155_FACTORY"),
                invalidPositionId,
                _parseDepositAmount(vm.readFile(_getJsonFilePath())),
                invalidData
            );
        }

        vm.stopBroadcast();
    }
}

contract SplitEverythingCheck is CSMJsonParser, FlatCFMJsonParser {
    function run() external {
        address depositor = vm.envAddress("DEPOSITOR");

        Market[] memory csms = _parseAllMarkets(vm.readFile(vm.envString("CSM_JSON")));
        uint256[] memory partition = _generatePartitionArray(csms.length + 1);

        {
            uint256 ctAllowance = IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))).allowance(
                depositor, vm.envAddress("CONDITIONAL_TOKENS")
            );

            vm.startBroadcast();

            console.log("=============================");
            console.log(
                (ctAllowance >= _parseDepositAmount(vm.readFile(_getJsonFilePath())))
                    ? unicode"✅ CT allowance ok"
                    : unicode"❌ CT allowance not set",
                "ConditionalTokens allowance:"
            );
            console.log(ctAllowance);
        }
        {
            uint256 erc1155BalanceInvalid = IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).balanceOf(
                depositor,
                IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).getPositionId(
                    IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))),
                    IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).getCollectionId(
                        bytes32(0), vm.envBytes32("CFM_CONDITION_ID"), partition[csms.length + 1 - 1]
                    )
                )
            );
            console.log("Invalid ERC1155 balance:");
            console.log(erc1155BalanceInvalid);
        }

        for (uint256 i = 0; i < csms.length; i++) {
            console.log("--------------------------");
            uint256 erc1155Balance = IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).balanceOf(
                depositor,
                IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).getPositionId(
                    IERC20(_parseCollateralAddress(vm.readFile(_getJsonFilePath()))),
                    IConditionalTokens(vm.envAddress("CONDITIONAL_TOKENS")).getCollectionId(
                        bytes32(0), vm.envBytes32("CFM_CONDITION_ID"), partition[i]
                    )
                )
            );
            console.log(
                (erc1155Balance >= _parseDepositAmount(vm.readFile(_getJsonFilePath())))
                    ? unicode"✅ splitPosition done"
                    : unicode"❌ splitPosition not done",
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
            console.log(
                (sbal >= _parseDepositAmount(vm.readFile(_getJsonFilePath())))
                    && (lbal >= _parseDepositAmount(vm.readFile(_getJsonFilePath()))) ? unicode"✅" : unicode"❌",
                "Short // Long // Invalid:"
            );
            console.logUint(sbal);
            console.logUint(lbal);
            console.logUint(ibal);
        }

        vm.stopBroadcast();
    }
}
