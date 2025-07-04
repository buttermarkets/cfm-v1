# SplitAndWrap Script

This script splits collateral tokens using a full discrete partition on Gnosis Conditional Tokens and automatically wraps the resulting ERC1155 position tokens into ERC20 tokens.

## Overview

The script performs the following operations:
1. Approves the ConditionalTokens contract to spend collateral
2. Splits the collateral into multiple outcome positions using a full discrete partition
3. Wraps each resulting ERC1155 position token into an ERC20 token using Wrapped1155Factory
4. The wrapped ERC20 tokens end up in the caller's wallet

## Environment Variables

The script requires the following environment variables:

- `COLLATERAL_TOKEN`: Address of the collateral token (ERC20)
- `AMOUNT`: Amount of collateral to split
- `CONDITION_ID`: The condition ID (bytes32) for the split
- `OUTCOME_COUNT`: Number of outcomes (must be > 0 and <= 256)
- `CONDITIONAL_TOKENS`: Address of the Gnosis ConditionalTokens contract
- `WRAPPED_1155_FACTORY`: Address of the Wrapped1155Factory contract

## Usage

### Running the split and wrap:

```bash
COLLATERAL_TOKEN=0x... \
AMOUNT=1000000000000000000 \
CONDITION_ID=0x... \
OUTCOME_COUNT=3 \
CONDITIONAL_TOKENS=0x... \
WRAPPED_1155_FACTORY=0x... \
forge script script/SplitAndWrap.s.sol:SplitAndWrap --rpc-url $RPC_URL --broadcast
```

### Checking the status:

```bash
# Check for the current sender
forge script script/SplitAndWrap.s.sol:SplitAndWrapCheck --rpc-url $RPC_URL

# Check for a specific user
USER=0x... forge script script/SplitAndWrap.s.sol:SplitAndWrapCheck --rpc-url $RPC_URL
```

## Full Discrete Partition

A full discrete partition means each outcome gets its own unique position. For example:
- With 3 outcomes: partition = [1, 2, 4] (binary: 001, 010, 100)
- With 4 outcomes: partition = [1, 2, 4, 8] (binary: 0001, 0010, 0100, 1000)

This ensures each outcome is independent and can be traded separately.

## Notes

- The script assumes the condition has already been prepared in the ConditionalTokens contract
- Make sure you have sufficient collateral balance before running
- The wrapped tokens are standard ERC20 tokens that can be traded on DEXs
- Each wrapped token represents a claim on the collateral if that specific outcome occurs
