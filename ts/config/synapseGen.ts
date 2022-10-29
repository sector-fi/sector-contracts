import fs from 'fs/promises';
import { ethers, getNamedAccounts, network } from 'hardhat';
import { ISynapseSwap, ISynapseMiniChef2 } from '../../typechain';
import { strategies } from './synapseConfigs';
import { getUniswapV3Path } from './utils';

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
  await addToConfig(strategy.name, config, strategy);
};

const addToConfig = async (key: string, data, stratConfig) => {
  const filePath = './ts/config/strategies.json';
  const jsonString: any = await fs.readFile(filePath, {
    encoding: 'utf8',
  });
  const config = JSON.parse(jsonString);
  config[key] = data;
  const typeKey = stratConfig.type + 'Strats';
  config[typeKey] = [...new Set([...config[typeKey], key])];
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), {
    encoding: 'utf8',
  });
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
