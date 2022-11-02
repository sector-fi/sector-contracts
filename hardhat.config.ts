import 'hardhat-deploy';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import env from 'dotenv';
import { subtask } from 'hardhat/config';
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from 'hardhat/builtin-tasks/task-names';
import '@nomiclabs/hardhat-etherscan';
import '@typechain/hardhat';
import '@nomiclabs/hardhat-ethers';

Error.stackTraceLimit = Infinity;

// This skips the test comilation
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
  async (_, __, runSuper) => {
    const paths = await runSuper();
    return paths.filter((p) => !p.includes('src/test'));
  }
);

env.config();

const {
  // roles
  OWNER,
  DEPLOYER,
  MANAGER,
  MANAGER2,
  GUARDIAN,
  TIMELOCK_ADMIN,

  // keys
  DEPLOYER_KEY, // key for prod deployment

  // config
  SHOW_GAS,
  FORK_CHAIN,

  // api keys for contract verification
  COIN_MARKET_CAP_API,
  FTM_API_KEY,
  SNOWTRACE_API_KEY,
  MOONRIVER_API_KEY,
  MOONBEAM_API_KEY,
  INFURA_API_KEY,
  FTM_TESTNET_API_KEY,
  ETHERSCAN_API_KEY,
  ARBITRUM_API_KEY,
  OPTIMISM_API_KEY,

  // rpc keys
  GOERLI_ALCHEMY,
  ALCHEMY_OP,
  ALCHEMY_ARB,
  ALCHEMY_KEY,
} = process.env;

const keys = [DEPLOYER_KEY].filter((k) => k != null);

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const config = {
  namedAccounts: {
    deployer: {
      default: DEPLOYER,
    },
    owner: {
      default: OWNER,
    },
    manager: {
      default: MANAGER,
    },
    guardian: {
      default: GUARDIAN,
    },
    timelockAdmin: {
      default: TIMELOCK_ADMIN,
    },
    manager2: {
      default: MANAGER2,
    },
    usdc: {
      mainnet: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      arbitrum: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
      optimism: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
      moonriver: '0xE3F5a90F9cb311505cd691a46596599aA1A0AD7D',
    },
    layerZeroEndpoint: {
      arbitrum: '0x3c2269811836af69497E5F486A85D7316753cf62',
      goerli: '0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23',
      fuji: '0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706',
      mainnet: '0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675',
      avalanche: '0x3c2269811836af69497E5F486A85D7316753cf62',
      fantom: '0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7',
      moonbean: '0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4',
      optimism: '0x3c2269811836af69497E5F486A85D7316753cf62',
      hardhat: '0x3c2269811836af69497E5F486A85D7316753cf62',
      localhost: '0x3c2269811836af69497E5F486A85D7316753cf62',
      fantom_testnet: '0x7dcAD72640F835B0FA36EFD3D6d3ec902C7E5acf',
    },
    multichainEndpoint: {
      fantom_testnet: '0xc629d02732EE932db1fa83E1fcF93aE34aBFc96B',
      goerli: '0x3D4e1981f822e87A1A4C05F2e4b3bcAdE5406AE3',
      default: '0xC10Ef9F491C9B59f936957026020C321651ac078',
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
      tags: [FORK_CHAIN],
      allowUnlimitedContractSize: true,
      supportMultichain: true,
      chains: {
        43114: {
          hardforkHistory: {
            arrowGlacier: 0,
          },
        },
        250: {
          hardforkHistory: {
            arrowGlacier: 0,
          },
        },
      },
      companionNetworks: {
        l1: 'arbitrum',
        l2: FORK_CHAIN,
        // l1: FORK_CHAIN,
        // l2: 'optimism',
      },
    },
    localhost: {
      chainId: 1337,
      accounts: keys.length ? keys : undefined,
      tags: [FORK_CHAIN],
      companionNetworks: {
        l1: FORK_CHAIN,
        l2: 'optimism',
      },
    },
    fantom: {
      url: 'https://rpc.ftm.tools/',
      gasPrice: 700e9,
      chainId: 250,
      layerZeroId: 112,
      supportMultichain: true,
      accounts: keys.length ? keys : undefined,
      tags: ['fantom'],
      verify: {
        etherscan: {
          apiKey: FTM_API_KEY,
          apiUrl: 'https://api.ftmscan.com/',
        },
      },
    },
    avalanche: {
      url: 'https://api.avax.network/ext/bc/C/rpc',
      gasPrice: 26.5e9,
      chainId: 43114,
      layerZeroId: 106,
      supportMultichain: true,
      accounts: keys.length ? keys : undefined,
      tags: ['avalanche'],
      verify: {
        etherscan: {
          apiKey: SNOWTRACE_API_KEY,
          apiUrl: 'https://api.snowtrace.io/',
        },
      },
    },
    moonriver: {
      url: 'https://rpc.api.moonriver.moonbeam.network',
      accounts: keys.length ? keys : undefined,
      chainId: 1285,
      layerZeroId: null,
      supportMultichain: true,
      gasPrice: 1.1e9,
      name: 'moonriver',
      tags: ['moonriver'],
      verify: {
        etherscan: {
          apiKey: MOONRIVER_API_KEY,
        },
      },
      companionNetworks: {
        l1: 'arbitrum',
      },
    },
    moonbeam: {
      url: 'https://rpc.api.moonbeam.network',
      accounts: keys.length ? keys : undefined,
      chainId: 1284,
      layerZeroId: 126,
      supportMultichain: false,
      gasPrice: 101e9,
      name: 'moonbeam',
      tags: ['moonbeam'],
      verify: {
        etherscan: {
          apiKey: MOONBEAM_API_KEY,
          apiUrl: 'https://api-moonbeam.moonscan.io',
        },
      },
    },
    goerli: {
      url: GOERLI_ALCHEMY,
      accounts: keys.length ? keys : undefined,
      chainId: 5,
      layerZeroId: 10121,
      supportMultichain: true,
      verify: {
        etherscan: {
          apiKey: ETHERSCAN_API_KEY,
          apiUrl: 'https://api-goerli.etherscan.io/',
        },
      },
    },
    fuji: {
      url: 'https://api.avax-test.network/ext/bc/C/rpc',
      accounts: keys.length ? keys : undefined,
      chainId: 43113,
      layerZeroId: 10106,
      supportMultichain: false,
      verify: {
        etherscan: {
          apiKey: SNOWTRACE_API_KEY,
          apiUrl: `https://api-testnet.snowtrace.io/api?apikey=${SNOWTRACE_API_KEY}`,
        },
      },
    },
    fantom_testnet: {
      url: 'https://rpc.testnet.fantom.network/',
      accounts: keys.length ? keys : undefined,
      chainId: 4002,
      layerZeroId: 10112,
      supportMultichain: true,
      verify: {
        etherscan: {
          apiKey: FTM_TESTNET_API_KEY,
          apiUrl: `https://api-testnet.ftmscan.com/api?apikey=${FTM_TESTNET_API_KEY}`,
        },
      },
    },
    arbitrum: {
      accounts: keys.length ? keys : undefined,
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_ARB}`,
      // url: `https://arbitrum-mainnet.infura.io/v3/${INFURA_API_KEY}`,
      chainId: 42161,
      layerZeroId: 110,
      supportMultichain: true,
      gasPrice: 0.1e9,
      name: 'arbitrum',
      tags: ['arbitrum'],
      verify: {
        etherscan: {
          apiKey: ARBITRUM_API_KEY,
          apiUrl: `https://api.arbiscan.io/api?apikey=${ARBITRUM_API_KEY}`,
        },
      },
      // companionNetworks: {
      //   l1: 'arbitrum',
      // },
    },
    optimism: {
      accounts: keys.length ? keys : undefined,
      url: `https://opt-mainnet.g.alchemy.com/v2/${ALCHEMY_OP}`,
      chainId: 10,
      layerZeroId: 111,
      supportMultichain: true,
      // gasPrice: 0.001e9,
      name: 'optimism',
      tags: ['optimism'],
      companionNetworks: {
        l1: 'arbitrum',
      },
      ovm: true,
      verify: {
        etherscan: {
          apiKey: OPTIMISM_API_KEY,
          apiUrl: `https://api-optimistic.etherscan.io/api?apikey=${OPTIMISM_API_KEY}`,
        },
      },
    },
    mainnet: {
      accounts: keys.length ? keys : undefined,
      url: 'https://mainnet.infura.io/v3/' + INFURA_API_KEY,
      gasPrice: 2.1e9,
      chainId: 1,
      layerZeroId: 101,
      supportMultichain: true,
    },
  },

  solidity: {
    compilers: [
      {
        version: '0.8.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  gasReporter: {
    enabled: SHOW_GAS === 'true',
    currency: 'USD',
    gasPrice: 1,
    coinmarketcap: COIN_MARKET_CAP_API,
  },
  paths: {
    sources: './src',
    cache: './hh-cache',
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  // etherscan: {
  //   apiKey: {
  //     moonbeam: MOONBEAM_API_KEY,
  //     goerli: ETHERSCAN_API_KEY,
  //   },
  // },
  external: {
    // this allows us to fork deployments (specify folders we can import deployments from)
    deployments: {
      localhost: FORK_CHAIN ? [`deployments/${FORK_CHAIN}`] : [],
      hardhat: FORK_CHAIN ? [`deployments/${FORK_CHAIN}`] : [],
    },
  },
};

export default {
  ...config,
  networks: {
    ...config.networks,
    hardhat: {
      ...config.networks.hardhat,
      chainId: FORK_CHAIN
        ? config.networks[FORK_CHAIN].chainId
        : config.networks.hardhat.chainId,
    },
  },
};
