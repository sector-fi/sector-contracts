import { ethers, getNamedAccounts, network } from 'hardhat';
import { ERC20__factory, ICurveV1Adapter } from '../../../typechain';
import { levConvex } from './config';
import { chainToEnv, getUniswapV3Path, addStratToConfig } from '../utils';
import { constants } from 'ethers';

const main = async () => {
  for (const strategy of levConvex) await addStrategy(strategy);
};

const addStrategy = async (strategy) => {
  const { deployer } = await getNamedAccounts();
  const curveAdapter: ICurveV1Adapter = await ethers.getContractAt(
    'ICurveV1Adapter',
    strategy.curveAdapter,
    deployer
  );
  const metapoolAddr = await curveAdapter.metapoolBase();

  let metapool: ICurveV1Adapter | undefined;
  if (metapoolAddr != constants.AddressZero) {
    metapool = (await ethers.getContractAt(
      'ICurveV1Adapter',
      metapoolAddr,
      deployer
    )) as ICurveV1Adapter;
  }

  // metaPool mean 3crv
  const nCoins = strategy.is3crv ? 3 : (await curveAdapter.nCoins()).toNumber();

  let coinId;
  let riskId = strategy.is3crv ? 0 : null;
  for (let i = 0; i < nCoins; i++) {
    console.log(curveAdapter.address, nCoins, i);
    const [coin] = await (metapool || curveAdapter).functions['coins(uint256)'](
      i
    );
    console.log(strategy.name, nCoins, coin, strategy.underlying);
    if (coin === strategy.underlying) coinId = i;
    if (coin == strategy.riskAsset) riskId = i;
  }
  if (coinId == null)
    throw new Error(`${strategy.name} coin not found in curve pool`);

  const convexRewardPool = await ethers.getContractAt(
    'IBaseRewardPool',
    strategy.convexRewardPool,
    deployer
  );
  const nRewards = await convexRewardPool.extraRewardsLength();
  console.log(strategy.name, 'nRewards', nRewards.toNumber());

  for (let i = 0; i < nRewards.toNumber(); i++) {
    const [extraRewardsAddr] = await convexRewardPool.functions[
      'extraRewards(uint256)'
    ](i);
    const rewardsPool = await ethers.getContractAt(
      'IBaseRewardPool',
      extraRewardsAddr,
      deployer
    );
    const rewardToken = await rewardsPool.rewardToken();
    console.log('extraRewardsAddr: ', extraRewardsAddr);
    console.log('found reward token: ', rewardToken);
    strategy.farmTokens.push(rewardToken);
  }
  console.log(strategy.name, strategy.farmTokens);

  strategy.harvestPaths = [];
  for (let j = 0; j < strategy.farmTokens.length; j++) {
    try {
      const path = await getUniswapV3Path(
        strategy.farmTokens[j],
        strategy.underlying
      );
      strategy.harvestPaths.push(path);
    } catch (e) {
      console.log('could not get path for ', strategy.farmTokens[j]);
      console.log(e);
    }
  }
  console.log(strategy.name, strategy.harvestPaths);

  const riskToken = await ethers.getContractAt(
    'ERC20',
    strategy.riskAsset,
    deployer
  );
  const riskDecimals = await riskToken.decimals();

  const config = {
    a1_curveAdapter: strategy.curveAdapter,
    a2_curveAdapterDeposit:
      strategy.curveAdapterDeposit || ethers.constants.AddressZero,
    a3_acceptsNativeToken: !!strategy.acceptsNativeToken,
    b_convexRewardPool: strategy.convexRewardPool,
    c_creditFacade: strategy.creditFacade,
    d_convexBooster: strategy.convexBooster,
    e1_coinId: coinId, // curve token index
    e2_riskId: riskId, // curve token index
    f1_underlying: strategy.underlying,
    f2_riskAsset: strategy.riskAsset,
    f3_riskAssetDecimals: riskDecimals,
    g_leverageFactor: strategy.leverageFactor,
    h_farmRouter: strategy.farmRouter,
    i_farmTokens: strategy.farmTokens,
    j_harvestPaths: strategy.harvestPaths,
    k_is3crv: !!strategy.is3crv,
    x_chain: chainToEnv[strategy.chain],
  };
  await addStratToConfig(strategy.name, config, strategy);
};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
