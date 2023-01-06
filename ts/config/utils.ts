import { ethers, getNamedAccounts, network } from 'hardhat';
import { AlphaRouter } from '@uniswap/smart-order-router';
import { Token, CurrencyAmount, TradeType } from '@uniswap/sdk-core';
import { encodeRouteToPath } from '@uniswap/v3-sdk';
import fs from 'fs/promises';

export const CONFIG_PATH = './ts/config/strategies.json';

export const chainToEnv = {
  optimism: 'OP',
  arbitrum: 'ARBITRUM',
  mainnet: 'ETH',
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

  // @ts-ignore
  const path = encodeRouteToPath(trade.trade.routes[0], false);
  return path;
};

export const addStratToConfig = async (key: string, data, stratConfig) => {
  const filePath = CONFIG_PATH;
  const jsonString: any = await fs.readFile(filePath, {
    encoding: 'utf8',
  });
  const config = JSON.parse(jsonString);
  config[key] = data;
  const typeKey = stratConfig.type + 'Strats';
  const typeStrats = config[typeKey] || [];
  config[typeKey] = [...new Set([...typeStrats, key])];
  await fs.writeFile(filePath, JSON.stringify(config, null, 2), {
    encoding: 'utf8',
  });
};
