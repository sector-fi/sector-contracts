const farms = {
  arbitrum: '0x73186f2Cf2493f20836b17b21ae79fc12934E207',
};

const tokens = {
  STG: '0x6694340fc020c5E6B96567843da2df01b2CE1eb6',
  ETH: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
  USDC: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
};

const uniswapRouter = {
  arbitrum: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
};

export const strategies = [
  {
    type: 'synapse',
    name: 'USDC-Arbitrum-Synapse',
    underlying: tokens.USDC,
    strategy: '0x9Dd329F5411466d9e0C488fF72519CA9fEf0cb40',
    farm: farms['arbitrum'],
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
];
