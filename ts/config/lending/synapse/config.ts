import { genStratName, StratType, tokens } from '../../utils';

const farms = {
  arbitrum: '0x73186f2Cf2493f20836b17b21ae79fc12934E207',
};

const uniswapRouter = {
  arbitrum: '0xE592427A0AEce92De3Edee1F18E0157C05861564',
};

const type = StratType.LND;

export const strategies = [
  {
    type: 'Synapse',
    name: genStratName(type, 'USDC', [], ['Synapse'], 'arbitrum'),
    underlying: tokens.arbitrum.USDC,
    // swap contract of the wrapper
    strategy: '0x9Dd329F5411466d9e0C488fF72519CA9fEf0cb40',
    farm: farms['arbitrum'],
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
  {
    type: 'Synapse',
    name: genStratName(type, 'ETH', [], ['Synapse'], 'arbitrum'),
    underlying: tokens.arbitrum.ETH,
    acceptsNativeToken: true,
    // SWAP contract of the SwapEthWrapper
    strategy: '0xa067668661C84476aFcDc6fA5D758C4c01C34352',
    farm: farms['arbitrum'],
    farmRouter: uniswapRouter['arbitrum'],
    chain: 'arbitrum',
  },
];
