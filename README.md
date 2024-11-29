# Butter Conditional Funding Markets Smart Contracts

## Codebase Structure

Main contracts live under `src/butter-v1`. Any other contract is either there
for reference, or might come useful at some point, or can be useful for testing
purposes.

Many contracts that live under `src` are contracts from Gnosis Conditional
Tokens that are merely ported versions of originals with minor modifications for
compatibility with the latest EVM and toolchain.

## The Design

`IMarket` is he API of market contracts. 

`IOracle` is the API of oracle contracts. It might make more sense to call this
IOracleAdapter, since it's an API of adapter contracts in practice.

`DecisionMarketFactory` creates `DecisionMarket`s and does the bookkeeping. 

`DecisionMarket` represents the condition of funding. It's a market but it won't
be traded. It creates a `ConditionalScalarMarket` for each outcome it has. It
prepares an oracle question and condition (as in `ConditionalTokens`) during
construction. 

`ConditionalScalarMarket` represents the scalar market which is on the condition
of parent `DecisionMarket`. This will be traded. It prepares an oracle question
and condition (as in `ConditionalTokens`) during construction. 

`ConditionalTokens` is the core contract that manages the creation and
redemption of conditional tokens. It's a port of Gnosis Conditional Tokens
framework with minor modifications for compatibility with the latest EVM and
toolchain.

`RealityAdapter` implements `IOracle` and Reality.ETH specific logic.

`QuestionTypes` defines the structure for different types of questions that can
create markets: scalar questions with upper/lower bounds and multicategorical
questions.

The system follows these general steps:
1. `DecisionMarketFactory` creates a new market `DecisionMarket` with specified
   parameters. And this automatically creates `ConditionalScalarMarket`s for
   each outcome.
   2. Each market prepares condition through ConditionalTokens and prepares
   question on oracle.
   3. Users split their collateral into scalar outcome tokens and can trade
   positions on scalar markets. (TODO)
   4. Oracle provides result. (Incomplete, needs to be verified for completeness
   and security)
   5. Market resolves and calculates payouts. (Incomplete, needs to be verified
   completeness and security)
   6. Users can redeem their positions for payouts (TODO. Depending on market
   making strategy, FPMM contract can be used, or we can use 3rd party AMMs
   introduce a middleman between `ConditionalTokens` and client which handles
   token wrapping during splits and merges, similar to how Seer handles this.)

   Things to consider:
- To prevent tight-coupling and have oracle modularity, markets do not know
  implementation details of Reality.ETH, and instead all Reality details go into
  `RealityAdapter` contract.
- In this application there are many tokens therefore user has to approve many
  token transaction. If possible these should be eliminated, perhaps via a
  custom logic in `ERC20.transfer()` function. At very least, we can use gasless
  token approvals to improve UX. 
- The question ID is important and can be an attack vector if it's not carefully
  considered. See:
  https://github.com/seer-pm/demo/blob/4943119bf6526ac4c8decf696703fb986ae6e66b/contracts/src/MarketFactory.sol#L295
  for example.
- We can use contract cloning pattern to reduce gas costs since the system is
  deploying almost identical contracts many times.
- There is a logic for string interpolation in `OracleAdapter` to encode a
  Reality question, and this complexity can be eliminated by creating a [Reality
  template](https://github.com/RealityETH/reality-eth-monorepo/blob/9e3e75d026269e8fee8eef8230bd3957c9bf2fb0/packages/contracts/development/contracts/RealityETH-4.0.sol#L120)
  and using it instead. 




# Todo:

- [x] Structure comments in FIXME/TODO
- [x] What to do about INVALID?
    - [ ] Build some docs
    - [ ] Make test scenarios or script simulations for these cases
- [x] Finish oracle integration & prepareQuestion
    - [x] Create template in Reality
        - 3 placeholders: "What will be the %s of %s?"
            - "success rate/TVL?"
            - Project name
    - [x] Put templateIds in OracleAdapter and not in DecisionMarket
    - [x] Collision problems
- [ ] Integrate FPMM OR use erc20 wrapper
    - [ ] First figure out if 1155 works well with Metamask
    - [ ] 1 FPMM factory call in ScalarMarket constructor
    - [ ]  if wrapping: contract which translates conditions between client and
      contract → see Router contract in Seer
- [ ] Make a View and events
    - [ ] events need to be done during coding
    - [ ] view can be done later
- [ ] Take a look into cloning contracts for gas savings
    - [ ] https://github.com/seer-pm/demo/blob/4943119bf6526ac4c8decf696703fb986ae6e66b/contracts/src/MarketFactory.sol#L18C11-L18C17
- [ ] Clean up/secure codebase
    - [ ] Review all comments
    - [ ] Review comments in the Seer codebase
    - [ ] Go through best practices (security, tests, conventions)
    - [ ] Compare to tests in Seer
- [ ] Update license
    - [ ] Update license
    - [ ] Squash all commits

For later:

- think about making approval better:
    - https://www.quicknode.com/guides/ethereum-development/transactions/how-to-use-erc20-permit-approval
- or rather, don't expect people to approve a function but rather send tokens to
  the market maker directly


# CFM

## design

### mechansim: flat-cfm

<insert description>

### oracle: invalid case

Reality can return
['invalid'](https://realityeth.github.io/docs/html/contracts.html?highlight=invalid)
in case the question can't be answered.

At the projects outcome level, an invalid case means CFM contracts can't figure
whether any project has succeeded in getting funded. Hence, it is equivalent to
the fact that none of the outcomes was returned by the oracle, ie that no
project got funded.

At the individual project level with a scalar outcome, invalid means that CFM's
scalar markets can't know how to reward traders. It thus means that the market
should return collateral deposits as-is, hence allow merging of tokens but not
redemption.  
This is imperfect as traders might feel abused as some of them will make a loss
(or a profit) in case this happens.
