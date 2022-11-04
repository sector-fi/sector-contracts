const stargateRouters = {
  arbitrum: '0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614',
};

const farms = {
  arbitrum: '0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176',
};
const tokens = {
  STG: '0x6694340fc020c5E6B96567843da2df01b2CE1eb6',
  ETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  USDC: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
};

const uniswapRouter = {
  arbitrum: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
};

export const stargate = [
  {
    type: 'stargate',
    poolId: 1, // get this from interface?
    name: 'USDC-Arbitrum-Stargate',
    underlying: tokens.USDC,
    strategy: stargateRouters['arbitrum'],
    farm: farms['arbitrum'],
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
];
