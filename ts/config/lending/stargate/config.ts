import { genStratName, StratType, tokens } from '../../utils';

const stargateRouters = {
  arbitrum: '0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614',
  optimism: '0xB0D502E938ed5f4df2E681fE6E419ff29631d62b',
};

const factory = {
  arbitrum: '0x55bDb4164D28FBaF0898e0eF14a589ac09Ac9970',
  optimism: '0xE3B53AF74a4BF62Ae5511055290838050bf764Df',
};

const farms = {
  arbitrum: '0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176',
  optimism: '0x4DeA9e918c6289a52cd469cAC652727B7b412Cd2',
};

const uniswapRouter = {
  arbitrum: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
  optimism: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
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
    underlying: tokens.arbitrum.ETH,
    stargateEth: tokens.arbitrum.SGETH,
    acceptsNativeToken: true,
    strategy: stargateRouters['arbitrum'],
    farm: farms['arbitrum'],
    farmOutput: tokens.arbitrum.ETH,
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
  {
    type: 'Stargate',
    // have to iterate through getPool in factory to get the right one...
    poolId: 1, // get this from interface?
    name: genStratName(type, 'USDC', [], ['Stargate'], 'optimism'),
    underlying: tokens.optimism.USDC,
    strategy: stargateRouters['optimism'],
    farm: farms['optimism'],
    farmRouter: uniswapRouter['optimism'],
    chain: 'optimism',
  },
  {
    type: 'Stargate',
    // have to iterate through getPool in factory to get the right one...
    poolId: 13, // get this from interface?
    name: genStratName(type, 'ETH', [], ['Stargate'], 'optimism'),
    underlying: tokens.optimism.ETH,
    stargateEth: tokens.optimism.SGETH,
    acceptsNativeToken: true,
    strategy: stargateRouters['optimism'],
    farm: farms['optimism'],
    farmRouter: uniswapRouter['optimism'],
    chain: 'optimism',
  },
];
