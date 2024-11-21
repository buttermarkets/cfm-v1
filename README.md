# Butter Conditional Funding Markets Smart Contracts

## Codebase Structure

Main contracts live under `src/butter-v1`. Any other contract is either there for reference, or might come useful at some point, or can be useful for testing purposes.

Many contracts that live under `src` are contracts from Gnosis Conditional Tokens that are merely ported versions of originals with minor modifications for compatibility with the latest EVM and toolchain.

## The Design

`IMarket` is he API of market contracts. 

`IOracle` is the API of oracle contracts. It might make more sense to call this IOracleAdapter, since it's an API of adapter contracts in practice.

`DecisionMarketFactory` creates `DecisionMarket`s and does the bookkeeping. 

`DecisionMarket` represents the condition of funding. It's a market but it won't be traded. It creates a `ConditionalScalarMarket` for each outcome it has. It prepares an oracle question and condition (as in `ConditionalTokens`) during construction. 

`ConditionalScalarMarket` represents the scalar market which is on the condition of parent `DecisionMarket`. This will be traded. It prepares an oracle question and condition (as in `ConditionalTokens`) during construction. 

`ConditionalTokens` is the core contract that manages the creation and redemption of conditional tokens. It's a port of Gnosis Conditional Tokens framework with minor modifications for compatibility with the latest EVM and toolchain.

`OracleAdapter` implements `IOracle` and oracle specific logic. In the current state it is implementing Reality.ETH.

`QuestionTypes` defines the structure for different types of questions that can create markets: scalar questions with upper/lower bounds and multicategorical questions.

The system follows these general steps:
1. `DecisionMarketFactory` creates a new market `DecisionMarket` with specified parameters. And this automatically creates `ConditionalScalarMarket`s for each outcome.
2. Each market prepares condition through ConditionalTokens and prepares question on oracle.
3. Users split their collateral into scalar outcome tokens and can trade positions on scalar markets. (TODO)
4. Oracle provides result. (Incomplete, needs to be verified for completeness and security)
5. Market resolves and calculates payouts. (Incomplete, needs to be verified completeness and security)
6. Users can redeem their positions for payouts (TODO. Depending on market making strategy, FPMM contract can be used, or we can use 3rd party AMMs introduce a middleman between `ConditionalTokens` and client which handles token wrapping during splits and merges, similar to how Seer handles this.)

Things to consider:
- To prevent tight-coupling and have oracle modularity, markets do not know implementation details of Reality.ETH, and instead all Reality details go into `OracleAdapter` contract. Considering `OracleAdapter` actually implements Reality oracle, it makes sense to call this contract `RealityAdapter` instead.
- In this application there are many tokens therefore user has to approve many token transaction. If possible these should be eliminated, perhaps via a custom logic in `ERC20.transfer()´ function. At very least, we can use gasless token approvals to improve UX. 
- The question ID is important and can be an attack vector if it's not carefully considered. See: https://github.com/seer-pm/demo/blob/4943119bf6526ac4c8decf696703fb986ae6e66b/contracts/src/MarketFactory.sol#L295 for example.
- We can use contract cloning pattern to reduce gas costs since the system is deploying almost identical contracts many times.
- There is a logic for string interpolation in `OracleAdapter` to encode a Reality question, and this complexity can be eliminated by creating a [Reality template](https://github.com/RealityETH/reality-eth-monorepo/blob/9e3e75d026269e8fee8eef8230bd3957c9bf2fb0/packages/contracts/development/contracts/RealityETH-4.0.sol#L120) and using it instead. 




## Toolkit: Foundry & Soldeer

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

[Soldeer](https://soldeer.xyz/) is used for Solidity dependencies.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
