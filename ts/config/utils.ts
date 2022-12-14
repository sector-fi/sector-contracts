import { ethers, getNamedAccounts, network } from 'hardhat';
import { AlphaRouter } from '@uniswap/smart-order-router';
import { Token, CurrencyAmount, TradeType } from '@uniswap/sdk-core';
import { encodeRouteToPath } from '@uniswap/v3-sdk';

export const chainTOEnv = {
  optimism: 'OP',
  arbitrum: 'ARBITRUM',
  ethereum: 'ETH',
};

export const getUniswapV3Path = async (token0: string, token1: string) => {
  const chainId = network.config.chainId!;
  const alphaRouter = new AlphaRouter({
    chainId,
    provider: ethers.provider,
  });

  const amount = ethers.utils.parseUnits('1');

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
