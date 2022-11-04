const factories = {
  optimism: {
    tarotVelours: '0xD7cABeF2c1fD77a31c5ba97C724B82d3e25fC83C',
  },
};

const tokens = {
  OP: '0x4200000000000000000000000000000000000042',
  USDC: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
};

// not uused
const VELO_ROUTER = '0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9';

export const imx = [
  {
    type: 'imx',
    name: 'USDC-OP-tarot-velo',
    pair: '0x2585d58367c9faccddecc7df05006cf7f0f3d18e', // address from interface - tarot vault or staked token
    factory: factories.optimism.tarotVelours,
    underlying: tokens.USDC,
    farmRouter: VELO_ROUTER,
    harvestPath: [tokens.USDC],
  },
];

export const stargate = [
  {
    type: 'stargate',
    name: 'USDC-Arbitrum-Stargate',
    pair: '0x2585d58367c9faccddecc7df05006cf7f0f3d18e', // address from interface - tarot vault or staked token
    factory: factories.optimism.tarotVelours,
    underlying: tokens.USDC,
    farmRouter: VELO_ROUTER,
    harvestPath: [tokens.USDC],
  },
];
