// SPDX-License-Identifier: GPL-3.0-or-later
// This contract is based on the Conditional Token Framework by Gnosis.
// Documentation: <https://docs.gnosis.io/conditionaltokens/>
// Repository: <https://github.com/gnosis/conditional-tokens-market-makers>
// Note: This contract is a port of the original work, with minor modifications for compatibility with the latest EVM and toolchain.

pragma solidity ^0.8.1;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/IERC1155Receiver.sol";
import {ConditionalTokens, CTHelpers} from "./ConditionalTokens.sol";
import {ConstructedCloneFactory} from "./ConstructedCloneFactory.sol";
import {FixedProductMarketMaker, FixedProductMarketMakerData} from "./FixedProductMarketMaker.sol";

contract FixedProductMarketMakerFactory is ConstructedCloneFactory, FixedProductMarketMakerData {
    event FixedProductMarketMakerCreation(
        address indexed creator,
        FixedProductMarketMaker fixedProductMarketMaker,
        ConditionalTokens indexed conditionalTokens,
        IERC20 indexed collateralToken,
        bytes32[] conditionIds,
        uint256 fee
    );

    FixedProductMarketMaker public implementationMaster;

    constructor() {
        implementationMaster = new FixedProductMarketMaker();
    }

    function cloneConstructor(bytes calldata consData) external override {
        (ConditionalTokens _conditionalTokens, IERC20 _collateralToken, bytes32[] memory _conditionIds, uint256 _fee) =
            abi.decode(consData, (ConditionalTokens, IERC20, bytes32[], uint256));

        _supportedInterfaces[_INTERFACE_ID_ERC165] = true;
        _supportedInterfaces[IERC1155Receiver.onERC1155Received.selector
            ^ IERC1155Receiver.onERC1155BatchReceived.selector] = true;

        conditionalTokens = _conditionalTokens;
        collateralToken = _collateralToken;
        conditionIds = _conditionIds;
        fee = _fee;

        uint256 atomicOutcomeSlotCount = 1;
        outcomeSlotCounts = new uint256[](conditionIds.length);
        for (uint256 i = 0; i < conditionIds.length; i++) {
            uint256 outcomeSlotCount = conditionalTokens.getOutcomeSlotCount(conditionIds[i]);
            atomicOutcomeSlotCount *= outcomeSlotCount;
            outcomeSlotCounts[i] = outcomeSlotCount;
        }
        require(atomicOutcomeSlotCount > 1, "conditions must be valid");

        collectionIds = new bytes32[][](conditionIds.length);
        _recordCollectionIDsForAllConditions(conditionIds.length, bytes32(0));
        require(positionIds.length == atomicOutcomeSlotCount, "position IDs construction failed!?");
    }

    function _recordCollectionIDsForAllConditions(uint256 conditionsLeft, bytes32 parentCollectionId) private {
        if (conditionsLeft == 0) {
            positionIds.push(CTHelpers.getPositionId(collateralToken, parentCollectionId));
            return;
        }

        conditionsLeft--;

        uint256 outcomeSlotCount = outcomeSlotCounts[conditionsLeft];

        collectionIds[conditionsLeft].push(parentCollectionId);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            _recordCollectionIDsForAllConditions(
                conditionsLeft, CTHelpers.getCollectionId(parentCollectionId, conditionIds[conditionsLeft], 1 << i)
            );
        }
    }

    function createFixedProductMarketMaker(
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] calldata conditionIds,
        uint256 fee
    ) external returns (FixedProductMarketMaker) {
        FixedProductMarketMaker fixedProductMarketMaker = FixedProductMarketMaker(
            createClone(
                address(implementationMaster), abi.encode(conditionalTokens, collateralToken, conditionIds, fee)
            )
        );
        emit FixedProductMarketMakerCreation(
            msg.sender, fixedProductMarketMaker, conditionalTokens, collateralToken, conditionIds, fee
        );
        return fixedProductMarketMaker;
    }
}
