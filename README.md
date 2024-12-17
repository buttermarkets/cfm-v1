# conditional funding markets (CFM)

## mechansim: flat-cfm

The mechanism implemented here is a simplified version of
[CFMs](https://community.ggresear.ch/t/conditional-funding-markets/27) called
["Flat CFM"](https://butterd.notion.site/cfm-v1-mech-v0-2-Flat-CFM-13657e477193802f8abce08cd13aa979?pvs=74).

## codebase status and caveats

Core contracts are in a stable state in terms of functionality and state
management.

We still plan on doing the following changes:

- Refactorings to ease testing.
- Improve tests.
- Add events.
- Add deployment scripts.
- Natspecs.
- Implement some gas savings.

## codebase structure

- `src/*`: Main contracts.
- `src/interfaces/*`: Interfaces to external contracts.
- `src/vendor/<github org name>/<github repo name>/*`: External contracts,
  ported to 8.20.0 as directly as possible.

**Note to auditors:** if checking the ported files is too time consuming and we
need to deploy these contracts on the chain that we end up choosing, we can
simply revert to deploying the original Solidity versions (0.5.x) of these
contracts which have already been audited. So please don't systematically
include auditing these contracts in the estimate.


## design

`DecisionMarket` represents the condition of funding. It's a market but it won't
be traded. It creates a `ConditionalScalarMarket` for each outcome it has. It
prepares an oracle question and condition (as in `ConditionalTokens`) during
construction. 

`ConditionalScalarMarket` represents the scalar market which is on the condition
of parent `DecisionMarket`. This will be traded. It prepares an oracle question
and condition (as in `ConditionalTokens`) during construction. 

`ConditionalTokens` is the core contract that manages the creation and
redemption of conditional tokens. It's a port of Gnosis Conditional Tokens
framework. We also rely on `Wrapped1155Factory` which enables wrapping 1155
outcome tokens in ERC20s so we can trade them on any AMM.  
Both these contracts were ported it to 8.20.0 with minor modifications for
compatibility. We expect to deploy them on chain whenever the network we choose
doesn't have a canonical deployment (for now, only mainnet and Gnosis Chain
have some). We use these contracts for testing purposes as well.

`CFMRealityAdapter` implements an adapter pattern to access RealityETH from our
contracts, with a normalized interface (we want to later enable oracle
agnosticity).

`QuestionTypes` defines basic data types for CFM decision questions, scalar
questions and nested conditional tokens.

The system follows these general steps:

1. `DecisionMarketFactory` creates a new `DecisionMarket` with specified
   parameters. And this automatically creates `ConditionalScalarMarket`s for
   each outcome.
1. The `DecisionMarket` prepares their condition through `ConditionalTokens` and
   submits and oracle question via `CFMRealityAdapter`.
1. Each `ConditionalScalarMarket` prepares their condition through
   `ConditionalTokens` and submits an oracle question via `CFMRealityAdapter`.
   Within a given `DecisionMarket`, each of these will have similar questions
   implemented by a common Reality template with a varying project name.
1. Users split their collateral into decision outcome tokens, then split again
   into scalar outcome tokens. These tokens are ERC20s and can be traded on
   AMMs.
1. When the oracle provides an answer to the decision question, the
   `DecisionMarket` can be resolved and calculates payouts.
1. When the oracle provides an answer to the conditional scalar questions (all
   together), all `ConditionalScalarMarket`s can be resolved and calculate
   payouts.
1. Users can redeem their positions for payouts.

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
  for example. We believe the code mitigates any such issue.
- We can use contract cloning pattern to reduce gas costs since the system is
  deploying almost identical contracts many times.


## oracle: invalid case

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
