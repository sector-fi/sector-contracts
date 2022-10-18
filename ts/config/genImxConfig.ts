import fs from 'fs/promises';
import { ethers, getNamedAccounts } from 'hardhat';
import { IIMXFactory, IVaultToken } from '../../typechain';
import { imx } from './config';

const main = async () => {
  imx.forEach(addIMXStrategy);
};

const addIMXStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const factory: IIMXFactory = await ethers.getContractAt(
    'IIMXFactory',
    strategy.factory,
    deployer
  );
  const { collateral } = await factory.getLendingPool(strategy.pair);
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

  const config = {
    a_underlying: strategy.underlying,
    b_short: strategy.underlying == token0 ? token1 : token0,
    c_uniPair: await poolToken.underlying(),
    d_poolToken: collateral,
    e_farmToken: rewardToken,
    f_farmRouter: strategy.farmRouter,
    g_chain: 'OP',
    h_harvestPath: [rewardToken, ...strategy.harvestPath],
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
