// SPDX-License-Identifier: GPL-3.0-or-later
// This contract is based on the Conditional Token Framework by Gnosis.
// Documentation: <https://docs.gnosis.io/conditionaltokens/>
// Repository: <https://github.com/gnosis/conditional-tokens-market-makers>
// Note: This contract is a port of the original work, with minor modifications
// for compatibility with the latest EVM and toolchain.

pragma solidity ^0.8.0;

import {ConditionalTokens} from "./ConditionalTokens.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./SafeMath.sol";

library CeilDiv {
    // calculates ceil(x/y)
    function ceildiv(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x > 0) return ((x - 1) / y) + 1;
        return x / y;
    }
}

// TODO: no need to wrap in ERC20 if we don't use it.
contract FixedProductMarketMaker is ERC20, ERC1155Holder {
    constructor() ERC20("", "") {}

    event FPMMFundingAdded(address indexed funder, uint256[] amountsAdded, uint256 sharesMinted);
    event FPMMFundingRemoved(
        address indexed funder, uint256[] amountsRemoved, uint256 collateralRemovedFromFeePool, uint256 sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint256 investmentAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint256 returnAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensSold
    );

    using SafeMath for uint256;
    using CeilDiv for uint256;

    uint256 constant ONE = 10 ** 18;

    ConditionalTokens public conditionalTokens;
    IERC20 public collateralToken;
    bytes32[] public conditionIds;
    uint256 public fee;
    uint256 internal feePoolWeight;

    uint256[] outcomeSlotCounts;
    bytes32[][] collectionIds;
    uint256[] positionIds;
    mapping(address => uint256) withdrawnFees;
    uint256 internal totalWithdrawnFees;

    function getPoolBalances() private view returns (uint256[] memory) {
        address[] memory thises = new address[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            thises[i] = address(this);
        }
        return conditionalTokens.balanceOfBatch(thises, positionIds);
    }

    function generateBasicPartition(uint256 outcomeSlotCount) private pure returns (uint256[] memory partition) {
        partition = new uint256[](outcomeSlotCount);
        for (uint256 i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
    }

    function splitPositionThroughAllConditions(uint256 amount) private {
        for (uint256 i = conditionIds.length - 1; int256(i) >= 0; i--) {
            uint256[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint256 j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.splitPosition(
                    // parentCollectionId: collectionIds[i][j] <- how does it get recorded?
                    // conditionId: conditionIds[i] <- why are there multiple conditions?
                    // partition: parition, full partition ([1,2,4…])
                    collateralToken,
                    collectionIds[i][j],
                    conditionIds[i],
                    partition,
                    amount
                );
            }
        }
    }

    function mergePositionsThroughAllConditions(uint256 amount) private {
        for (uint256 i = 0; i < conditionIds.length; i++) {
            uint256[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for (uint256 j = 0; j < collectionIds[i].length; j++) {
                conditionalTokens.mergePositions(
                    collateralToken, collectionIds[i][j], conditionIds[i], partition, amount
                );
            }
        }
    }

    function collectedFees() external view returns (uint256) {
        return feePoolWeight.sub(totalWithdrawnFees);
    }

    function feesWithdrawableBy(address account) public view returns (uint256) {
        uint256 rawAmount = feePoolWeight.mul(balanceOf(account)) / totalSupply();
        return rawAmount.sub(withdrawnFees[account]);
    }

    function withdrawFees(address account) public {
        uint256 rawAmount = feePoolWeight.mul(balanceOf(account)) / totalSupply();
        uint256 withdrawableAmount = rawAmount.sub(withdrawnFees[account]);
        if (withdrawableAmount > 0) {
            withdrawnFees[account] = rawAmount;
            totalWithdrawnFees = totalWithdrawnFees.add(withdrawableAmount);
            require(collateralToken.transfer(account, withdrawableAmount), "withdrawal transfer failed");
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal {
        if (from != address(0)) {
            withdrawFees(from);
        }

        uint256 totalSupply = totalSupply();
        uint256 withdrawnFeesTransfer = totalSupply == 0 ? amount : feePoolWeight.mul(amount) / totalSupply;

        if (from != address(0)) {
            withdrawnFees[from] = withdrawnFees[from].sub(withdrawnFeesTransfer);
            totalWithdrawnFees = totalWithdrawnFees.sub(withdrawnFeesTransfer);
        } else {
            feePoolWeight = feePoolWeight.add(withdrawnFeesTransfer);
        }
        if (to != address(0)) {
            withdrawnFees[to] = withdrawnFees[to].add(withdrawnFeesTransfer);
            totalWithdrawnFees = totalWithdrawnFees.add(withdrawnFeesTransfer);
        } else {
            feePoolWeight = feePoolWeight.sub(withdrawnFeesTransfer);
        }
    }

    function addFunding(uint256 addedFunds, uint256[] calldata distributionHint) external {
        require(addedFunds > 0, "funding must be non-zero");

        uint256[] memory sendBackAmounts = new uint256[](positionIds.length);
        uint256 poolShareSupply = totalSupply();
        uint256 mintAmount;
        if (poolShareSupply > 0) {
            require(distributionHint.length == 0, "cannot use distribution hint after initial funding");
            uint256[] memory poolBalances = getPoolBalances();
            uint256 poolWeight = 0;
            for (uint256 i = 0; i < poolBalances.length; i++) {
                uint256 balance = poolBalances[i];
                if (poolWeight < balance) {
                    poolWeight = balance;
                }
            }

            for (uint256 i = 0; i < poolBalances.length; i++) {
                uint256 remaining = addedFunds.mul(poolBalances[i]) / poolWeight;
                sendBackAmounts[i] = addedFunds.sub(remaining);
            }

            mintAmount = addedFunds.mul(poolShareSupply) / poolWeight;
        } else {
            if (distributionHint.length > 0) {
                require(distributionHint.length == positionIds.length, "hint length off");
                uint256 maxHint = 0;
                for (uint256 i = 0; i < distributionHint.length; i++) {
                    uint256 hint = distributionHint[i];
                    if (maxHint < hint) {
                        maxHint = hint;
                    }
                }

                for (uint256 i = 0; i < distributionHint.length; i++) {
                    uint256 remaining = addedFunds.mul(distributionHint[i]) / maxHint;
                    require(remaining > 0, "must hint a valid distribution");
                    sendBackAmounts[i] = addedFunds.sub(remaining);
                }
            }

            mintAmount = addedFunds;
        }

        require(collateralToken.transferFrom(msg.sender, address(this), addedFunds), "funding transfer failed");
        require(collateralToken.approve(address(conditionalTokens), addedFunds), "approval for splits failed");
        splitPositionThroughAllConditions(addedFunds);

        _mint(msg.sender, mintAmount);

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, positionIds, sendBackAmounts, "");

        // transform sendBackAmounts to array of amounts added
        for (uint256 i = 0; i < sendBackAmounts.length; i++) {
            sendBackAmounts[i] = addedFunds.sub(sendBackAmounts[i]);
        }

        emit FPMMFundingAdded(msg.sender, sendBackAmounts, mintAmount);
    }

    function removeFunding(uint256 sharesToBurn) external {
        uint256[] memory poolBalances = getPoolBalances();

        uint256[] memory sendAmounts = new uint256[](poolBalances.length);

        uint256 poolShareSupply = totalSupply();
        for (uint256 i = 0; i < poolBalances.length; i++) {
            sendAmounts[i] = poolBalances[i].mul(sharesToBurn) / poolShareSupply;
        }

        uint256 collateralRemovedFromFeePool = collateralToken.balanceOf(address(this));

        _burn(msg.sender, sharesToBurn);
        collateralRemovedFromFeePool = collateralRemovedFromFeePool.sub(collateralToken.balanceOf(address(this)));

        conditionalTokens.safeBatchTransferFrom(address(this), msg.sender, positionIds, sendAmounts, "");

        emit FPMMFundingRemoved(msg.sender, sendAmounts, collateralRemovedFromFeePool, sharesToBurn);
    }

    function onERC1155Received(
        address operator,
        address, /*from*/
        uint256, /*id*/
        uint256, /*value*/
        bytes memory /*data*/
    ) public view override returns (bytes4) {
        if (operator == address(this)) {
            return this.onERC1155Received.selector;
        }
        return 0x0;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory, /*ids*/
        uint256[] memory, /*values*/
        bytes memory /*data*/
    ) public view override returns (bytes4) {
        if (operator == address(this) && from == address(0)) {
            return this.onERC1155BatchReceived.selector;
        }
        return 0x0;
    }

    function calcBuyAmount(uint256 investmentAmount, uint256 outcomeIndex) public view returns (uint256) {
        require(outcomeIndex < positionIds.length, "invalid outcome index");

        uint256[] memory poolBalances = getPoolBalances();
        uint256 investmentAmountMinusFees = investmentAmount.sub(investmentAmount.mul(fee) / ONE);
        uint256 buyTokenPoolBalance = poolBalances[outcomeIndex];
        uint256 endingOutcomeBalance = buyTokenPoolBalance.mul(ONE);
        for (uint256 i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint256 poolBalance = poolBalances[i];
                endingOutcomeBalance =
                    endingOutcomeBalance.mul(poolBalance).ceildiv(poolBalance.add(investmentAmountMinusFees));
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return buyTokenPoolBalance.add(investmentAmountMinusFees).sub(endingOutcomeBalance.ceildiv(ONE));
    }

    function calcSellAmount(uint256 returnAmount, uint256 outcomeIndex)
        public
        view
        returns (uint256 outcomeTokenSellAmount)
    {
        require(outcomeIndex < positionIds.length, "invalid outcome index");

        uint256[] memory poolBalances = getPoolBalances();
        uint256 returnAmountPlusFees = returnAmount.mul(ONE) / ONE.sub(fee);
        uint256 sellTokenPoolBalance = poolBalances[outcomeIndex];
        uint256 endingOutcomeBalance = sellTokenPoolBalance.mul(ONE);
        for (uint256 i = 0; i < poolBalances.length; i++) {
            if (i != outcomeIndex) {
                uint256 poolBalance = poolBalances[i];
                endingOutcomeBalance =
                    endingOutcomeBalance.mul(poolBalance).ceildiv(poolBalance.sub(returnAmountPlusFees));
            }
        }
        require(endingOutcomeBalance > 0, "must have non-zero balances");

        return returnAmountPlusFees.add(endingOutcomeBalance.ceildiv(ONE)).sub(sellTokenPoolBalance);
    }

    function buy(uint256 investmentAmount, uint256 outcomeIndex, uint256 minOutcomeTokensToBuy) external {
        uint256 outcomeTokensToBuy = calcBuyAmount(investmentAmount, outcomeIndex);
        require(outcomeTokensToBuy >= minOutcomeTokensToBuy, "minimum buy amount not reached");

        require(collateralToken.transferFrom(msg.sender, address(this), investmentAmount), "cost transfer failed");

        uint256 feeAmount = investmentAmount.mul(fee) / ONE;
        feePoolWeight = feePoolWeight.add(feeAmount);
        uint256 investmentAmountMinusFees = investmentAmount.sub(feeAmount);
        require(
            collateralToken.approve(address(conditionalTokens), investmentAmountMinusFees), "approval for splits failed"
        );
        splitPositionThroughAllConditions(investmentAmountMinusFees);

        conditionalTokens.safeTransferFrom(address(this), msg.sender, positionIds[outcomeIndex], outcomeTokensToBuy, "");

        emit FPMMBuy(msg.sender, investmentAmount, feeAmount, outcomeIndex, outcomeTokensToBuy);
    }

    function sell(uint256 returnAmount, uint256 outcomeIndex, uint256 maxOutcomeTokensToSell) external {
        uint256 outcomeTokensToSell = calcSellAmount(returnAmount, outcomeIndex);
        require(outcomeTokensToSell <= maxOutcomeTokensToSell, "maximum sell amount exceeded");

        conditionalTokens.safeTransferFrom(
            msg.sender, address(this), positionIds[outcomeIndex], outcomeTokensToSell, ""
        );

        uint256 feeAmount = returnAmount.mul(fee) / (ONE.sub(fee));
        feePoolWeight = feePoolWeight.add(feeAmount);
        uint256 returnAmountPlusFees = returnAmount.add(feeAmount);
        mergePositionsThroughAllConditions(returnAmountPlusFees);

        require(collateralToken.transfer(msg.sender, returnAmount), "return transfer failed");

        emit FPMMSell(msg.sender, returnAmount, feeAmount, outcomeIndex, outcomeTokensToSell);
    }
}

// for proxying purposes
contract FixedProductMarketMakerData {
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    uint256 internal _totalSupply;

    bytes4 internal constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    mapping(bytes4 => bool) internal _supportedInterfaces;

    event FPMMFundingAdded(address indexed funder, uint256[] amountsAdded, uint256 sharesMinted);
    event FPMMFundingRemoved(
        address indexed funder, uint256[] amountsRemoved, uint256 collateralRemovedFromFeePool, uint256 sharesBurnt
    );
    event FPMMBuy(
        address indexed buyer,
        uint256 investmentAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensBought
    );
    event FPMMSell(
        address indexed seller,
        uint256 returnAmount,
        uint256 feeAmount,
        uint256 indexed outcomeIndex,
        uint256 outcomeTokensSold
    );

    ConditionalTokens internal conditionalTokens;
    IERC20 internal collateralToken;
    bytes32[] internal conditionIds;
    uint256 internal fee;
    uint256 internal feePoolWeight;

    uint256[] internal outcomeSlotCounts;
    bytes32[][] internal collectionIds;
    uint256[] internal positionIds;
    mapping(address => uint256) internal withdrawnFees;
    uint256 internal totalWithdrawnFees;
}
