import { ethers, getNamedAccounts, network } from 'hardhat';
import { ICurveV1Adapter } from '../../../typechain';
import { levConvex } from './config';
import { chainToEnv, getUniswapV3Path, addStratToConfig } from '../utils';

const main = async () => {
  levConvex.filter((s) => s.chain === network.name).forEach(addStrategy);
};

const addStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const curveAdapter: ICurveV1Adapter = await ethers.getContractAt(
    'ICurveV1Adapter',
    strategy.curveAdapter,
    deployer
  );
  const nCoins = await curveAdapter.nCoins();

  let coinId;
  for (let i = 0; i < nCoins.toNumber(); i++) {
    const [coin] = await curveAdapter.functions['coins(uint256)'](i);
    if (coin === strategy.underlying) {
      coinId = i;
      break;
    }
  }
  if (coinId == null) throw new Error('coin not found in curve pool');

  strategy.harvestPaths = [];
  for (let j = 0; j < strategy.farmTokens.length; j++) {
    const path = await getUniswapV3Path(
      strategy.farmTokens[j],
      strategy.underlying
    );
    strategy.harvestPaths.push(path);
  }
  console.log(strategy.harvestPaths);

  const config = {
    a1_curveAdapter: strategy.curveAdapter,
    a2_acceptsNativeToken: !!strategy.acceptsNativeToken,
    b_convexRewardPool: strategy.convexRewardPool,
    c_creditFacade: strategy.creditFacade,
    d_convexBooster: strategy.convexBooster,
    e_coinId: coinId, // curve token index
    f_underlying: strategy.underlying,
    g_leverageFactor: strategy.leverageFactor,
    h_farmRouter: strategy.farmRouter,
    i_farmTokens: strategy.farmTokens,
    j_harvestPaths: strategy.harvestPaths,
    x_chain: chainToEnv[strategy.chain],
  };
  await addStratToConfig(strategy.name, config, strategy);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
