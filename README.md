# Sector Contracts

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

see coverage stats:

```
yarn coverage
```

install this plugin:
https://marketplace.visualstudio.com/items?itemName=ryanluker.vscode-coverage-gutters

run `yarn coverage:lcov`
then run `Display Coverage` via Command Pallate

## Previous Audits

`src/strategies/hlp` has been previously audited but does have some implementation changes: https://github.com/scion-finance/contracts/tree/dev/audits

# Vault Architecture

There are two types of Sector vaults:

- EIP4626 or Aggregator vaults: these are vaults that aggregate multiple strategies and can allocate funds between them.
- EIP5115 or SCYVault: ERC20 wrappers & management utils for individual strategies

## ScyVaults (EIP5115) - Single Strategy Vaults

ScyVaults are based on the EIP 5115 proposal: [https://ethereum-magicians.org/t/eip-5115-super-composable-yield-token/9423](https://ethereum-magicians.org/t/eip-5115-super-composable-yield-token/9423)

These vaults act as a wrapper for a given strategy.

### **Accounting:**

Accounting is based on the LP token of the strategy. For example Uniswap pair LP, or Compound cTokens. This is similar to yield farm aggregator strategies (like Beefy or Pickle), however these vaults accept `underlying` deposits in currencies other than the accounting asset.

Asset flow:

1. User deposits underlying, ex: USDC
2. Strategy executes trades or loans and deposits funds into a yield-generating protocol, ex: buy ETH with half of the USDC balance in order to deposit into the ETH/USDC Uniswap pool
3. LP tokens are converted to vault tokens based on current exchange rate
4. Final vault token output is checked against user-provided slippage parameters to prevent front-running and sandwich attacks.

These vaults are protected from flash loans as long as the LP asset underlying the vault cannot be manipulated via flash loans (ex: Uniswap LP tokens).

**Deposits** are instantaneous.
**Withdrawals** are instantaneous in SCYVault and are epoch-based in SCYVaultWEpoch

### **Deposits:**

There two ways to deposit ERC20 tokens into SCYVaults

1. EOA Acconts
   1. approve ERC20
   2. call `deposit()` with `amountTokenToPull = depositAmount`
2. Contracts
   1. push ERC20 tokens to vault or strategy (this avoids the approval step)
      1. if `sendERC20ToStrategy = true` push funds to `vault.strategy`
      2. if `sendERC20ToStrategy = false` push funds to `vault`
   2. call `deposit()` with `amountTokenToPull = 0`

For native token deposits (i.e. ETH) both EOA accounts and Contracts should call `deposit()` with `amountTokenToPull = 0` and deposit amount included as `tx.value`

[Flowchart Maker & Online Diagram Software](https://app.diagrams.net/#G1OyNFh5PdfoaREGg4fsDylv0Uy57q-OOz)

### Profits/Harvest

During harvests, all reward tokens are swapped to underlying and re-deposited into the respective strategy.

## AggregatorVaults

Aggregator vaults aggregate ScyVault strategies.

### **Accounting:**

Accounting is similar to yearn finance vaults and is denominated in the underlying currency of the vaults. To prevent manipulation, the `MANAGER` role is responsible for maintaining the exchange rate between vault tokens and underlying asset.

### **Deposits:**

Deposits happen instantaneously.

### **Withdrawals:**

Withdrawals happen via a two-step process to prevent vault token price manipulation.

### **EmergencyWithdrawal:**

In case `MANAGER` refuses to process withdrawals, users are able to redeem vault tokens for the strategy tokens the vault holds.

### Profits/Harvest

All profits are converted to underlying and auto-compounded by depositing into the strategy.

# Strategies

More info on strategies here:

[Strategy Overview](https://www.notion.so/Strategy-Overview-ff27376952494f84b657ec757fbff74e)

## HLP - Hedge Uniswap LP

Single-sided Uniswap 2 farming.

**Detailed strategy docs**: [https://docs.scion.finance/how-it-works/delta-neutral-yield-farming](https://docs.scion.finance/how-it-works/delta-neutral-yield-farming)

Additional contract notes: [https://github.com/scion-finance/contracts#hedgedlp](https://github.com/scion-finance/contracts#hedgedlp)

**Audits:** [https://github.com/scion-finance/contracts/tree/dev/audits](https://github.com/scion-finance/contracts/tree/dev/audits)

**Changes since previous audits:**

The strategy was modified to work with ScyVault accounting. Specifically [\_increasePosition](https://github.com/scion-finance/sector-contracts/blob/fb7b0ec044273a94706493a031df2df5f7ed9a37/src/strategies/hlp/HLPCore.sol#L278) and [\_decreasePosition](https://github.com/scion-finance/sector-contracts/blob/fb7b0ec044273a94706493a031df2df5f7ed9a37/src/strategies/hlp/HLPCore.sol#L244) have been modified to keep the the portfolio balance constant (previously deposits and withdrawals partially re-balanced the portfolio).

## IMX - One-sided leveraged yield farming

This strategy is similar to HLP, but it utilized the Impermax protocol for borrowing assets.

# Auth Roles

Owner - all critical interactions will be behind a Timelock

- Single account
- Add / remove vaults and strategies
- Emergency action (arbitrary actions initiated from inside the contract)
- Add / remove GUARDIAN or MANAGER (DEFAULT_ADMIN_ROLE)

GUARDIAN - cold wallet or multisig, no time delay

- Set non-critical vault or strategy params ex:
  - Slippage max bounds
  - Rebalance threshold
  - Any other params to limit Manager actions
- Add / remove MANAGER ( Manager admin)

MANAGER - hot wallet / bot

- Process deposits and withdrawals (allowed to move funds between vaults / strategies) but not custodial
- Rebalance strategies
- Harvest strategies
