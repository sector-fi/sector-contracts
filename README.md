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

src/strategies/hlp has been previously audited but does have some implementation changes: https://github.com/scion-finance/contracts/tree/dev/audits
