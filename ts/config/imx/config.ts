import { genStratName, StratType, tokens } from '../utils';

const factories = {
  optimism: {
    tarotVelours: '0xD7cABeF2c1fD77a31c5ba97C724B82d3e25fC83C',
    Jupiter: '0x49df1fe24caf1a7dcbb2e2b1793b93b04edb62bf',
    Opaline: '0x1d90fdac4dd30c3ba38d53f52a884f6e75d0989e',
  },
  arbitrum: {
    tarotGalahad: '0x2217AEC3440E8FD6d49A118B1502e539f88Dba55',
    // tarotUlysses: '0x4B6daE049A35196A773028B2E835CCcCe9DD4723',
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

const type = StratType.LLP;

export const imx = [
  // {
  //   name: genStratName(type, 'USDC', ['TAROT'], ['Tarot', 'Velo'], 'optimism'),
  //   pair: '0xc73adf1da8847f0d8a4d1c17d2d2b3861ea577ae', // address from interface - tarot vault or staked token
  //   underlying: tokens.optimism.USDC,
  //   ...veloDexConfig,
  // },
  // {
  //   name: genStratName(type, 'USDC', ['VELO'], ['Tarot', 'Velo'], 'optimism'),
  //   pair: '0x287f9681af590354d6722ac51e6935beef631941', // address from interface - tarot vault or staked token
  //   underlying: tokens.optimism.USDC,
  //   ...veloDexConfig,
  // },
  // {
  //   name: genStratName(type, 'USDC', ['OP'], ['Tarot', 'Velo'], 'optimism'),
  //   pair: '0x2585d58367c9faccddecc7df05006cf7f0f3d18e', // address from interface - tarot vault or staked token
  //   underlying: tokens.optimism.USDC,
  //   ...veloDexConfig,
  // },
  {
    name: genStratName(type, 'USDC', ['ETH'], ['Tarot', 'Velo'], 'optimism'),
    pair: '0x6CFE820EC919a4AcCd651aC336197CE8A19539c7', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.USDC,
    ...veloDexConfig,
  },
  {
    name: genStratName(type, 'ETH', ['USDC'], ['Tarot', 'Velo'], 'optimism'),
    pair: '0x6CFE820EC919a4AcCd651aC336197CE8A19539c7', // address from interface - tarot vault or staked token
    underlying: tokens.optimism.ETH,
    acceptsNativeToken: true,
    ...veloDexConfig,
  },

  {
    name: genStratName(type, 'USDC', ['ETH'], ['Tarot', 'Xcal'], 'arbitrum'),
    pair: '0xc52cd7727920f0af088378d7192e2f19a22b861e',
    underlying: tokens.arbitrum.USDC,
    ...xcalConfig,
  },
  {
    name: genStratName(type, 'ETH', ['USDC'], ['Tarot', 'Xcal'], 'arbitrum'),
    pair: '0xc52cd7727920f0af088378d7192e2f19a22b861e',
    underlying: tokens.arbitrum.ETH,
    ...xcalConfig,
  },
  // {
  //   name: genStratName(type, 'USDC', ['XCAL'], ['Tarot', 'Xcal'], 'arbitrum'),
  //   pair: '0x54c3ef83c1941334c80db459399c398b20e02d4c',
  //   underlying: tokens.arbitrum.USDC,
  //   ...xcalConfig,
  // },
];
