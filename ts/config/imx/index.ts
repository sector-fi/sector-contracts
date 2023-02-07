import { ethers, getNamedAccounts, network } from 'hardhat';
import { IIMXFactory, IVaultToken } from '../../../typechain';
import { imx } from './config';
import { chainToEnv, addStratToConfig, StratType } from '../utils';

const main = async () => {
  const strats = imx.filter((s) => s.chain === network.name);
  for (const strategy of strats) {
    await addIMXStrategy(strategy);
  }
};

const addIMXStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const factory: IIMXFactory = await ethers.getContractAt(
    'IIMXFactory',
    strategy.factory,
    deployer
  );

  const { collateral } = await factory.getLendingPool(strategy.pair);
  if (collateral === ethers.constants.AddressZero)
    throw new Error('BAD Factory');

  const poolToken: IVaultToken = await ethers.getContractAt(
    'IVaultToken',
    strategy.pair,
    deployer
  );

  const token0 = await poolToken.token0();
  const token1 = await poolToken.token1();
  // this is incorrect
  // note tarot has no rewards
  const rewardToken = await poolToken.rewardsToken();

  console.log(strategy.name, factory.address);
  // console.log(strategy.underlying, token1, token0);

  const config = {
    a1_underlying: strategy.underlying,
    a2_acceptsNativeToken: !!strategy.acceptsNativeToken,
    b_short:
      strategy.underlying.toLowerCase() == token0.toLowerCase()
        ? token1
        : token0,
    c0_uniPair: await poolToken.underlying(),
    c1_pairRouter: strategy.pairRouter,
    d_poolToken: collateral,
    e_farmToken: rewardToken,
    f_farmRouter: strategy.farmRouter,
    h_harvestPath: [rewardToken, ...strategy.harvestPath],
    x_chain: chainToEnv[strategy.chain],
  };

  strategy.type = StratType.LLP;
  await addStratToConfig(strategy.name, config, strategy);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
