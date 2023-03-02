import { genStratName, StratType, tokens } from '../../utils';

const stargateRouters = {
  arbitrum: '0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614',
};

const factory = {
  arbitrum: '0x55bDb4164D28FBaF0898e0eF14a589ac09Ac9970',
};

const farms = {
  arbitrum: '0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176',
};

const uniswapRouter = {
  arbitrum: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
};

const type = StratType.LND;

export const stargate = [
  {
    type: 'Stargate',
    poolId: 1, // get this from interface?
    name: genStratName(type, 'USDC', [], ['Stargate'], 'arbitrum'),
    underlying: tokens.arbitrum.USDC,
    strategy: stargateRouters['arbitrum'],
    farm: farms['arbitrum'],
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
  {
    type: 'Stargate',
    // have to iterate through getPool in factory to get the right one...
    poolId: 13, // get this from interface?
    name: genStratName(type, 'ETH', [], ['Stargate'], 'arbitrum'),
    underlying: tokens.arbitrum.SGETH,
    acceptsNativeToken: true,
    strategy: stargateRouters['arbitrum'],
    farm: farms['arbitrum'],
    farmOutput: tokens.arbitrum.ETH,
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
];
