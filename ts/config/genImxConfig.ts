import fs from 'fs/promises';
import { ethers, getNamedAccounts } from 'hardhat';
import { IIMXFactory, IVaultToken } from '../../typechain';

const factories = {
  optimism: {
    tarotVelours: '0xD7cABeF2c1fD77a31c5ba97C724B82d3e25fC83C',
  },
};

const tokens = {
  OP: '0x4200000000000000000000000000000000000042',
  USDC: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
};
const VELO_ROUTER = '0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9';

/// get pair from ui URL
const PAIR = '0x2585d58367c9faccddecc7df05006cf7f0f3d18e';
const UNDERLYING = tokens.USDC;
const NAME = 'USDC-OP-tarot-velo';

const main = async () => {
  const { deployer } = await getNamedAccounts();
  const factory: IIMXFactory = await ethers.getContractAt(
    'IIMXFactory',
    factories.optimism.tarotVelours,
    deployer
  );
  const { collateral } = await factory.getLendingPool(PAIR);
  const poolToken: IVaultToken = await ethers.getContractAt(
    'IVaultToken',
    PAIR,
    deployer
  );
  const token0 = await poolToken.token0();
  const token1 = await poolToken.token1();
  const rewardToken = await poolToken.rewardsToken();

  const config = {
    a_underlying: UNDERLYING,
    b_short: UNDERLYING == token0 ? token1 : token0,
    c_uniPair: await poolToken.underlying(),
    d_poolToken: collateral,
    e_farmToken: rewardToken,
    f_farmRouter: VELO_ROUTER,
    g_chain: 'OP',
    h_harvestPath: [rewardToken, tokens.USDC],
  };
  await addToConfig(NAME, config);
};

const addToConfig = async (key: string, data) => {
  const filePath = './ts/config/strategies.json';
  const jsonString: any = await fs.readFile(filePath, {
    encoding: 'utf8',
  });
  const config = JSON.parse(jsonString);
  config[key] = data;
  config.strats = [...new Set([...config.strats, key])];
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), {
    encoding: 'utf8',
  });
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
