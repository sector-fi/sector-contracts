import { ethers, getNamedAccounts, network } from 'hardhat';
import { ERC20__factory, IIMXFactory, IVaultToken } from '../../../typechain';
import { strategies } from './config';
import { chainToEnv, addStratToConfig, StratType } from '../utils';

const main = async () => {
  const strats = strategies.filter((s) => s.chain === network.name);
  for (const strategy of strats) {
    await addStrategy(strategy);
  }
};

const addStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  // const factory: IIMXFactory = await ethers.getContractAt(
  //   'IIMXFactory',
  //   strategy.factory,
  //   deployer
  // );

  // const { collateral } = await factory.getLendingPool(strategy.pair);
  // if (collateral === ethers.constants.AddressZero)
  //   throw new Error('BAD Factory');

  // const poolToken: IVaultToken = await ethers.getContractAt(
  //   'IVaultToken',
  //   strategy.pair,
  //   deployer
  // );

  // const token0 = await poolToken.token0();
  // const token1 = await poolToken.token1();
  // const rewardToken = await poolToken.rewardsToken();

  const config = {
    a_underlying: strategy.underlying,
    b_short: strategy.short,
    c_uniPair: strategy.uniPair,
    d1_cTokenLend: strategy.cTokenLend,
    d2_cTokenBorrow: strategy.cTokenBorrow,
    e1_farmToken: strategy.farmToken,
    e2_farmId: strategy.farmId,
    e3_uniFarm: strategy.uniFarm,
    f_farmRouter: strategy.farmRouter,
    h_harvestPath: strategy.harvestPath,
    l1_comptroller: strategy.comptroller,
    l2_lendRewardToken: strategy.lendRewardToken,
    l3_lendRewardPath: strategy.lendRewardPath,
    l4_lendRewardRouter: strategy.lendRewardRouter,
    l5_lenderType: strategy.lenderType,
    n_nativeToken: strategy.nativeToken,
    o_contract: strategy.contract,
    x_chain: chainToEnv[strategy.chain],
  };

  const signer = await ethers.getSigner(deployer);
  const underlying = await ERC20__factory.connect(strategy.underlying, signer);
  const short = await ERC20__factory.connect(strategy.short, signer);

  // additional export data for frontend
  const exportConfig = {
    underlyingDec: await underlying.decimals(),
    shortDec: await short.decimals(),
  };

  await addStratToConfig(strategy.name, config, strategy, exportConfig);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
