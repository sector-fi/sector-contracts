const factories = {
  optimism: {
    tarotVelours: '0xD7cABeF2c1fD77a31c5ba97C724B82d3e25fC83C',
  },
  arbitrum: {
    tarotGalahad: '0x2217AEC3440E8FD6d49A118B1502e539f88Dba55',
    // tarotUlysses: '0x4B6daE049A35196A773028B2E835CCcCe9DD4723',
  },
};

const tokens = {
  optimism: {
    ETH: '0x4200000000000000000000000000000000000006',
    OP: '0x4200000000000000000000000000000000000042',
    USDC: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
    VELO: '0x3c8B650257cFb5f272f799F5e2b4e65093a11a05',
    TAROT: '0x375488F097176507e39B9653b88FDc52cDE736Bf',
  },
  arbitrum: {
    USDC: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    ETH: '0x82af49447d8a07e3bd95bd0d56f35241523fbab1',
    XCAL: '0xd2568acCD10A4C98e87c44E9920360031ad89fCB',
  },
};

const VELO_ROUTER = '0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9';
const XCAL_ROUTER = '0x8e72bf5A45F800E182362bDF906DFB13d5D5cb5d';

const xcalConfig = {
  pairRouter: XCAL_ROUTER,
  factory: factories.arbitrum.tarotGalahad,
  farmRouter: XCAL_ROUTER,
  harvestPath: [],
  chain: 'arbitrum',
};

const veloDexConfig = {
  pairRouter: VELO_ROUTER,
  factory: factories.optimism.tarotVelours,
  farmRouter: VELO_ROUTER,
  harvestPath: [],
  chain: 'optimism',
};

export const imx = [
  {
    type: 'imx',
    name: 'USDC-TAROT-Tarot-Velo',
    pair: '0xc73adf1da8847f0d8a4d1c17d2d2b3861ea577ae', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.USDC,
    ...veloDexConfig,
  },
  {
    type: 'imx',
    name: 'USDC-VELO-Tarot-Velo',
    pair: '0x287f9681af590354d6722ac51e6935beef631941', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.USDC,
    ...veloDexConfig,
  },
  // {
  //   type: 'imx',
  //   name: 'USDC-OP-Tarot-Velo',
  //   pair: '0x2585d58367c9faccddecc7df05006cf7f0f3d18e', // address from interface - tarot vault or staked token
  //   underlying: tokens.USDC,
  //   ...veloDexConfig,
  // },
  {
    type: 'imx',
    name: 'USDC-ETH-Tarot-Velo',
    pair: '0x6CFE820EC919a4AcCd651aC336197CE8A19539c7', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.USDC,
    ...veloDexConfig,
  },
  {
    type: 'imx',
    name: 'ETH-USDC-Tarot-Velo',
    pair: '0x6CFE820EC919a4AcCd651aC336197CE8A19539c7', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.ETH,
    acceptsNativeToken: true,
    ...veloDexConfig,
  },

  {
    type: 'imx',
    name: 'USDC-ETH-Tarot-Xcal',
    pair: '0xc52cd7727920f0af088378d7192e2f19a22b861e',
    underlying: tokens.arbitrum.USDC,
    ...xcalConfig,
  },
  {
    type: 'imx',
    name: 'USDC-XCAL-Tarot-Xcal',
    pair: '0x54c3ef83c1941334c80db459399c398b20e02d4c',
    underlying: tokens.arbitrum.USDC,
    ...xcalConfig,
  },
];
