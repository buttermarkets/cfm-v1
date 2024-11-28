// SPDX-License-Identifier: GPL-3.0-or-later
// This contract is based on the Conditional Token Framework by Gnosis.
// Documentation: <https://docs.gnosis.io/conditionaltokens/>
// Repository: <https://github.com/gnosis/conditional-tokens-market-makers>
// Note: This contract is a port of the original work, with minor modifications for compatibility with the latest EVM and toolchain.

pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ConditionalTokens, CTHelpers} from "./ConditionalTokens.sol";

import {FixedProductMarketMaker, FixedProductMarketMakerData} from "./FixedProductMarketMaker.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Create2CloneFactory} from "./Create2CloneFactory.sol";

contract FPMMDeterministicFactory is Create2CloneFactory, FixedProductMarketMakerData, ERC1155Holder {
    event FixedProductMarketMakerCreation(
        address indexed creator,
        FixedProductMarketMaker fixedProductMarketMaker,
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] conditionIds,
        uint256 fee
    );

    FixedProductMarketMaker public implementationMaster;
    address internal currentFunder;

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

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes memory data)
        public
        override
        returns (bytes4)
    {
        ConditionalTokens(msg.sender).safeTransferFrom(address(this), currentFunder, id, value, data);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override returns (bytes4) {
        ConditionalTokens(msg.sender).safeBatchTransferFrom(address(this), currentFunder, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    function create2FixedProductMarketMaker(
        uint256 saltNonce,
        ConditionalTokens conditionalTokens,
        IERC20 collateralToken,
        bytes32[] calldata conditionIds,
        uint256 fee,
        uint256 initialFunds,
        uint256[] calldata distributionHint
    ) external returns (FixedProductMarketMaker) {
        FixedProductMarketMaker fixedProductMarketMaker = FixedProductMarketMaker(
            create2Clone(
                address(implementationMaster),
                saltNonce,
                abi.encode(conditionalTokens, collateralToken, conditionIds, fee)
            )
        );
        emit FixedProductMarketMakerCreation(
            msg.sender, fixedProductMarketMaker, conditionalTokens, collateralToken, conditionIds, fee
        );

        if (initialFunds > 0) {
            currentFunder = msg.sender;
            collateralToken.transferFrom(msg.sender, address(this), initialFunds);
            collateralToken.approve(address(fixedProductMarketMaker), initialFunds);
            fixedProductMarketMaker.addFunding(initialFunds, distributionHint);
            fixedProductMarketMaker.transfer(msg.sender, fixedProductMarketMaker.balanceOf(address(this)));
            currentFunder = address(0);
        }

        return fixedProductMarketMaker;
    }
}
