import { ethers, getNamedAccounts, network } from 'hardhat';
import { ERC20__factory, IIMXFactory, IVaultToken } from '../../../typechain';
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

  const shortAddr =
    strategy.underlying.toLowerCase() == token0.toLowerCase() ? token1 : token0;

  const config = {
    a1_underlying: strategy.underlying,
    a2_acceptsNativeToken: !!strategy.acceptsNativeToken,
    b_short: shortAddr,
    c0_uniPair: await poolToken.underlying(),
    c1_pairRouter: strategy.pairRouter,
    d_poolToken: collateral,
    e_farmToken: rewardToken,
    f_farmRouter: strategy.farmRouter,
    h_harvestPath: [rewardToken, ...strategy.harvestPath],
    x_chain: chainToEnv[strategy.chain],
  };

  const singer = await ethers.getSigner(deployer);
  const underlying = await ERC20__factory.connect(strategy.underlying, singer);
  const short = await ERC20__factory.connect(shortAddr, singer);

  // additional export data for frontend
  const exportConfig = {
    underlyingDec: await underlying.decimals(),
    shortDec: await short.decimals(),
  };

  strategy.type = StratType.LLP;
  await addStratToConfig(strategy.name, config, strategy, exportConfig);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
