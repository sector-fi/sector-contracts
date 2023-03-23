import { genStratName, StratType, tokens } from '../../utils';

const type = StratType.LND;

const OP_ETH = '0xabCC0531d4Cf0B4d6A92f1e5668696033a96f6D2';
const OP_USDC = '0xeBe70Ea3ff5fe44A22185870F46A9d092958Db69';
const ARB_USDC = '0x074e82153303ec002CBD996FebD148321E1302cE';
const ARB_ETH = '0x38b00d3FfB648f443C3DAF16f215F9E99c74bAa8';

export const strategies = [
  {
    type: 'imxLend',
    name: genStratName(type, 'USDC', ['ETH'], ['Tarot'], 'optimism'),
    underlying: tokens.optimism.USDC,
    strategy: OP_USDC,
    chain: 'optimism',
  },
  {
    type: 'imxLend',
    name: genStratName(type, 'ETH', ['USDC'], ['Tarot'], 'optimism'),
    underlying: tokens.optimism.ETH,
    acceptsNativeToken: true,
    strategy: OP_ETH,
    chain: 'optimism',
  },

  {
    type: 'imxLend',
    name: genStratName(type, 'USDC', ['ETH'], ['Tarot'], 'arbitrum'),
    underlying: tokens.arbitrum.USDC,
    strategy: ARB_USDC,
    chain: 'arbitrum',
  },
  {
    type: 'imxLend',
    name: genStratName(type, 'ETH', ['USDC'], ['Tarot'], 'arbitrum'),
    underlying: tokens.arbitrum.ETH,
    acceptsNativeToken: true,
    strategy: ARB_ETH,
    chain: 'arbitrum',
  },
];
