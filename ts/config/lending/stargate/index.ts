import fs from 'fs/promises';
import { ethers, getNamedAccounts, network } from 'hardhat';
import {
  IStargateRouter,
  IStargateFactory,
  IStargatePool,
  IStarchef,
} from '../../../../typechain';
import { stargate } from './config';
import {
  getUniswapV3Path,
  addStratToConfig,
  StratType,
  chainToEnv,
} from '../../utils';

export const main = async () => {
  const strategies = stargate.filter((s) => s.chain == network.name);
  for (const strategy of strategies) await addStrategy(strategy);
};

const addStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const router: IStargateRouter = await ethers.getContractAt(
    'IStargateRouter',
    strategy.strategy,
    deployer
  );

  const factory: IStargateFactory = await ethers.getContractAt(
    'IStargateFactory',
    await router.factory(),
    deployer
  );

  const pool: IStargatePool = await ethers.getContractAt(
    'IStargatePool',
    await factory.getPool(strategy.poolId),
    deployer
  );

  const farm: IStarchef = await ethers.getContractAt(
    'IStarchef',
    strategy.farm,
    deployer
  );

  const farmToken = await farm.stargate();

  const allPools = await farm.poolLength();
  let farmId;
  let i;
  for (i = 0; i < allPools.toNumber(); i++) {
    const { lpToken } = await farm.poolInfo(i);
    if (lpToken == pool.address) {
      farmId = i;
      break;
    }
  }
  if (i != farmId) throw new Error('farmId not found');

  const path = await getUniswapV3Path(farmToken, strategy.underlying);

  const config = {
    a_underlying: strategy.underlying,
    b_strategy: strategy.strategy,
    c_strategyId: strategy.poolId,
    d_yieldToken: pool.address,
    e_farmId: farmId,
    f1_farm: strategy.farm,
    f2_farmToken: farmToken,
    g_farmRouter: strategy.farmRouter,
    h_harvestPath: path,
    x_chain: chainToEnv[strategy.chain],
  };
  await addStratToConfig(strategy.name, config, strategy);
};
