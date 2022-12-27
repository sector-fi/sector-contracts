import { ethers, getNamedAccounts, network } from 'hardhat';
import { ISynapseSwap, ISynapseMiniChef2 } from '../../../typechain';
import { strategies } from './synapseConfigs';
import { getUniswapV3Path, addStratToConfig } from '../utils';

const main = async () => {
  strategies.filter((s) => s.chain == network.name).forEach(addStrategy);
};

const addStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const pool: ISynapseSwap = await ethers.getContractAt(
    'ISynapseSwap',
    strategy.strategy,
    deployer
  );

  const { lpToken } = await pool.swapStorage();

  const farm: ISynapseMiniChef2 = await ethers.getContractAt(
    'ISynapseMiniChef2',
    strategy.farm,
    deployer
  );

  const farmToken = await farm.SYNAPSE();

  const allPools = await farm.poolLength();
  let farmId;
  let i;
  for (i = 0; i < allPools.toNumber(); i++) {
    const farmLp = await farm.lpToken(i);
    if (lpToken == farmLp) {
      farmId = i;
      break;
    }
  }
  if (i != farmId) throw new Error('farmId not found');

  const path = await getUniswapV3Path(farmToken, strategy.underlying);
  const tokenId = await pool.getTokenIndex(strategy.underlying);

  const config = {
    a_underlying: strategy.underlying,
    b_strategy: strategy.strategy,
    c_strategyId: tokenId,
    d_yieldToken: lpToken,
    e_farmId: farmId,
    f1_farm: strategy.farm,
    f2_farmToken: farmToken,
    g_farmRouter: strategy.farmRouter,
    h_harvestPath: path,
    x_chain: 'ARBITRUM',
  };
  await addStratToConfig(strategy.name, config, strategy);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
