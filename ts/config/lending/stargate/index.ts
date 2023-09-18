import fs from 'fs/promises';
import { getNamedAccounts, network, ethers } from 'hardhat';
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
  tokens,
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

  const farmToken = getFarmToken(strategy.chain);

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

  console.log('get path', strategy.name, farmToken, strategy.underlying);
  let path;
  try {
    path = await getUniswapV3Path(
      farmToken,
      strategy.farmOutput || strategy.underlying
    );
  } catch (e) {
    console.log(
      'failed to get path',
      strategy.name,
      farmToken,
      strategy.underlying,
      e
    );
  }

  const config = {
    a_underlying: strategy.underlying,
    b_strategy: strategy.strategy,
    c_strategyId: strategy.poolId,
    d1_yieldToken: pool.address,
    d2_acceptsNativeToken: !!strategy.acceptsNativeToken,
    d3_stargateEth: strategy.stargateEth || ethers.constants.AddressZero,
    e_farmId: farmId,
    f1_farm: strategy.farm,
    f2_farmToken: farmToken,
    g_farmRouter: strategy.farmRouter,
    h_harvestPath: path,
    x_chain: chainToEnv[strategy.chain],
  };
  await addStratToConfig(strategy.name, config, strategy);
};

const getFarmToken = (chain) => {
  switch (chain) {
    case 'arbitrum':
      return tokens['arbitrum'].ARB;
    case 'optimism':
      return tokens['optimism'].OP;
    default:
      throw new Error('missing stargate rewards token');
  }
};
