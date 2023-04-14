import { ethers } from 'hardhat';
import { genStratName, StratType, tokens } from '../utils';

const type = StratType.HLP;

export const strategies = [
  {
    name: genStratName(type, 'USDC', ['ETH'], ['Velo'], 'optimism'),
    contract: 'VeloAave',
    underlying: tokens.optimism.USDC,
    short: tokens.optimism.ETH,
    uniPair: '0x79c912FEF520be002c2B6e57EC4324e260f38E50', // ETH/USDC Velodrome pair

    // auto fill?
    cTokenLend: '0x625E7708f30cA75bfd92586e17077590C60eb4cD', // aUSDC
    cTokenBorrow: '0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8', // variable DEBT ETH
    /// @dev address of the lending pool
    comptroller: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',

    farmToken: '0x3c8B650257cFb5f272f799F5e2b4e65093a11a05', // velo
    farmId: 0, // not needed
    uniFarm: '0xE2CEc8aB811B648bA7B1691Ce08d5E800Dd0a60a', // gauge
    farmRouter: '0xa132DAB612dB5cB9fC9Ac426A0Cc215A3423F9c9', // velo router
    harvestPath: [
      '0x3c8B650257cFb5f272f799F5e2b4e65093a11a05',
      tokens.optimism.ETH,
      tokens.optimism.USDC,
    ],

    lendRewardToken: ethers.constants.AddressZero,
    lendRewardPath: [],
    lendRewardRouter: ethers.constants.AddressZero,
    nativeToken: 2,
    lenderType: 'aave',
    chain: 'optimism',
  },
];
