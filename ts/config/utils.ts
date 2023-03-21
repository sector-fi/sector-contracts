import { ethers, getNamedAccounts, network } from 'hardhat';
import { AlphaRouter } from '@uniswap/smart-order-router';
import { Token, CurrencyAmount, TradeType } from '@uniswap/sdk-core';
import { encodeRouteToPath } from '@uniswap/v3-sdk';
import fs from 'fs/promises';

export const CONFIG_PATH = './ts/config/strategies.json';
export const EXPORT_PATH = './ts/config/strategiesExport.json';

export const tokens = {
  mainnet: {
    USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
    WETH: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    CRV: '0xD533a949740bb3306d119CC777fa900bA034cd52',
    CVX: '0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B',
    SNX: '0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F',
    GEAR: '0xBa3335588D9403515223F109EdC4eB7269a9Ab5D',
    sUSD: '0x57Ab1ec28D129707052df4dF418D58a2D46d5f51',
    gUSD: '0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd',
    lUSD: '0x5f98805A4E8be255a32880FDeC7F6728C6568bA0',
    FRAX: '0x853d955aCEf822Db058eb8505911ED77F175b99e',
  },
  optimism: {
    WETH: '0x121ab82b49B2BC4c7901CA46B8277962b4350204',
    ETH: '0x4200000000000000000000000000000000000006',
    OP: '0x4200000000000000000000000000000000000042',
    USDC: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
    VELO: '0x3c8B650257cFb5f272f799F5e2b4e65093a11a05',
    TAROT: '0x375488F097176507e39B9653b88FDc52cDE736Bf',
    STG: '0x296F55F8Fb28E498B858d0BcDA06D955B2Cb3f97',
    SGETH: '0xb69c8CBCD90A39D8D3d3ccf0a3E968511C3856A0',
  },
  arbitrum: {
    USDC: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    ETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    XCAL: '0xd2568acCD10A4C98e87c44E9920360031ad89fCB',
    STG: '0x6694340fc020c5E6B96567843da2df01b2CE1eb6',
    SGETH: '0x82CbeCF39bEe528B5476FE6d1550af59a9dB6Fc0',
  },
};

export const chainToEnv = {
  optimism: 'OP',
  arbitrum: 'ARBITRUM',
  mainnet: 'ETH',
};

export enum StratType {
  LevCVX = 'LCVX',
  LLP = 'LLP',
  HLP = 'HLP',
  LND = 'LND',
}

export const genStratName = (
  type: StratType,
  underlying: string,
  otherAssets: string[],
  protocols: string[],
  chain: string
) => {
  const assets = [underlying, ...otherAssets];
  return `${type}_${assets.join('-')}_${protocols.join('-')}_${chain}`;
};

export const getUniswapV3Path = async (token0: string, token1: string) => {
  const chainId = network.config.chainId!;
  const alphaRouter = new AlphaRouter({
    chainId,
    provider: ethers.provider,
  });

  const amount = ethers.utils.parseUnits('100');

  const TOKEN0 = new Token(chainId, token0, 18);
  const TOKEN1 = new Token(chainId, token1, 18);

  const trade = await alphaRouter.route(
    CurrencyAmount.fromRawAmount(TOKEN0, amount.toString()),
    TOKEN1,
    TradeType.EXACT_INPUT
  );
  if (!trade) throw new Error('no trade found');

  // console.log(trade.trade.routes[0].pools);
  // @ts-ignore
  const path = encodeRouteToPath(trade.trade.routes[0], false);
  return path;
};

export const addStratToConfig = async (
  key: string,
  data,
  stratConfig,
  additionalData = {}
) => {
  await _addStratToConfig(key, data, stratConfig, CONFIG_PATH);
  // we export a separate json with extra data for the frontend
  await _addStratToConfig(
    key,
    { ...data, ...additionalData },
    stratConfig,
    EXPORT_PATH
  );
};

const _addStratToConfig = async (key: string, data, stratConfig, filePath) => {
  const jsonString: any = await fs.readFile(filePath, {
    encoding: 'utf8',
  });
  const config = JSON.parse(jsonString);
  config[key] = data;
  const typeKey = '_list_' + stratConfig.type;
  const typeStrats = config[typeKey] || [];
  config[typeKey] = [...new Set([...typeStrats, key])];
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), {
    encoding: 'utf8',
  });
};
