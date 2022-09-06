# Scion Contracts

## WIP Contracts and files (ignore)

- /src/strategies/IMX.sol
- /src/mixins/IIMXFarm.sol
- /src/implementations/USDCimxWEVE.sol
- /src/adapters/IMXFarm.sol
- /test/imx-integration.sol

## Running Tests

install deps

```
yarn
```

init submodules

```
git submodule update --init --recursive
```

install [foundry](https://github.com/foundry-rs/foundry)

foundry tests:

```
yarn test
```

hardhat integrations tests:

```
yarn test:hardhat
```

## Coverage

hardhat integration coverage:

```
yarn cover // alias for npx hardhat coverage
```

limited forge test coverage (cannot do abstract contracts yet, so strategy doesn't have stats):

```
yarn coverage <Contract.sol>
```

## Fork network

fork and deploy fesh contracts to local network:

```
yarn fork <network_name>
```

fork and use already deployed contracts:

```
yarn fork <network_name> --no-reset
```

## Strategies

### BaseStrategy

This is a wrapper that provides an interface for the vault to interact with and tracks `shares` and `totalSupply`. Only `vault` is allowed to deposit or withdraw from the strategy so we don't have a need for an ERC20 to track shares.

### HedgedLP

(inherits from is `BaseStrategy`)

This is our first strategy, it takes deposits in `underlying`, sends a portion to a lending protocol as collateral, borrows `short` and provides `underlying/short` as liquidity to a Uniswap dex. On each `deposit` or `withdrawal` we increase or decrease our position.

When the price of the `short` asset moves wrt the `underlying` our `shortLP` position will begin to diverge from our `borrowedPosition`. A rebalance is required to restore the the balance. This usually involves in either trading some of the `underlying` for `short` and repaying a portion of the loan, or borrowing more in order to buy more `underlying`. This function is performed by the `manager` role.

The strategy manager is also responsible for harvesting the LP farm. This is done by calling the `harvest` method and providing appropriate slippage parameters.

A public `rebalanceLoan` method is available for anyone to call if the loan position gets close to liquidation. This will enable an external `keeper` network like Gelato to ensure the safty of the position.

### Mixins

`HedgedLP` uses abstract mixins to interact with lending and dex protocols. These mixina are agnostic to the concrete implementation of the protocol.

### Adapters

Adapters are contrete implementations of the lending and dex mixins for specific protocols.

## Security: Swaps & sandwitch/flashloan attacks:

### Underlying <-> Short Swaps

`underlying/short` swaps that happen as part of `deposit`, `withdraw`, `rebalance` and `closePosition` are protected against flash-swap attacks by the `checkPrice` modifier. This modifier queries the prices via the oracle used by the lending protocol (usually chainlink) and checks them against the current dex spot price.

### Vault Attacks

VaultUpgradable.sol implements `LockedProfit` (like in yearn vaults) and additionally `LockedLoss`. This prevents a flashwap or sandwich attack where an attacker may potentially manipulate the value of one of the strategies to either inflate or deflate the price of shares.

`lossSinceHarvest` is implemented to compute losses incurred in strategies since last harvest. This is to prevent withdrawal frontrunning where user who withdraw before the next harvest do not incur any losses. This mechanism is missing from the original Rari code and the exploit is outline in the following audits:

- https://github.com/Rari-Capital/vaults/blob/main/audits/yAcademy/Dhurv.Kat.Amanusk.pdf
- https://github.com/Rari-Capital/vaults/blob/main/audits/yAcademy/Nibbler.Bebis.Zokunei.Carl.pdf

### Harvest swaps

Swaps necessary as part of harvest operations take a `min` output amount computed externally.

## Permissions Architecture

### Strategies

- Public - can call `rebalanceLoan` when strategy is close to liquidation
- Vault - can deposit (`mint`) and withdraw (`redeemUnderlying`) from the strategy
- Owner - can set critical parameters & set manager
- Manager - `closePosition`, `setMaxTvl`, `rebalance` (not as critical) and `harvest` - critical because of the ability to set slippage params for swaps

### Vault

- Public - can call `deposit`, `withdraw`, `pushToWithdrawalQueueValidated` and `cleanWithdrawalQueue`
- Owner - can add new strategies, set critical parameters, & set manager
- Manager
  - `harvest` vault
  - manage assets via `depositIntoStrategy` and `withdrawFromStrategy`
  - set non-critcal configs like `maxTvl`
  - manage `withdrawalQueue`
  - `seizeStrategy` can withdraw any tokens from the strategy and send them to the `owner` (Timelock contract)

![permissions architecture](https://github.com/scion-finance/contracts/blob/dev/docs/permissions.png?raw=true)
