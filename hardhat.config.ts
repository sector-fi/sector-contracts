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
    return paths.filter((p) => !p.includes('src/tests'));
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

  ETHERSCAN_API_KEY,

  // rpc keys
  GOERLI_ALCHEMY,
  ALCHEMY_OP,
} = process.env;

const keys = [DEPLOYER_KEY].filter((k) => k != null);

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
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
    },
    layerZeroEndpoint: {
      goerli: "0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23",
      fuji: "0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706",
      mainnet: "0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675",
      avalanche: "0x3c2269811836af69497E5F486A85D7316753cf62",
      fantom: "0xb6319cC6c8c27A8F5dAF0dD3DF91EA35C4720dd7",
      moonbean: "0x9740FF91F1985D8d2B71494aE1A2f723bb3Ed9E4",
      optimism: "0x3c2269811836af69497E5F486A85D7316753cf62"
    },
    multichainEndpoint: {
      default: "0xC10Ef9F491C9B59f936957026020C321651ac078"
    }
  },
  networks: {
    hardhat: {
      chainId: 1337,
      tags: [FORK_CHAIN],
      allowUnlimitedContractSize: true,
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
    },
    localhost: {
      // accounts: keys.length ? keys : undefined,
      tags: [FORK_CHAIN],
    },
    fantom: {
      url: 'https://rpc.ftm.tools/',
      gasPrice: 700e9,
      chainId: 250,
      layerZeroId: 112,
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
      gasPrice: 1.1e9,
      name: 'moonriver',
      tags: ['moonriver'],
      verify: {
        etherscan: {
          apiKey: MOONRIVER_API_KEY,
        },
      },
    },
    moonbeam: {
      url: 'https://rpc.api.moonbeam.network',
      accounts: keys.length ? keys : undefined,
      chainId: 1284,
      layerZeroId: 126,
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
      chainId: 420,
      layerZeroId: 10121,
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
      verify: {
        etherscan: {
          apiKey: ETHERSCAN_API_KEY,
          apiUrl: 'https://api-goerli.etherscan.io/',
        },
      },
    },
    optimism: {
      url: `https://opt-mainnet.g.alchemy.com/v2/${ALCHEMY_OP}`,
      chainId: 10,
      layerZeroId: 111,
      gasPrice: 0.001e9,
      name: 'optimism',
      tags: ['optimism'],
    },
    mainnet: {
      accounts: keys.length ? keys : undefined,
      url: 'https://mainnet.infura.io/v3/' + INFURA_API_KEY,
      gasPrice: 2.1e9,
      chainId: 1,
      layerZeroId: 101,
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
    gasPrice: 30,
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
  etherscan: {
    apiKey: {
      moonbeam: MOONBEAM_API_KEY,
      goerli: ETHERSCAN_API_KEY,
    },
  },
  external: {
    // this allows us to fork deployments (specify folders we can import deployments from)
    deployments: {
      localhost: FORK_CHAIN ? [`deployments/${FORK_CHAIN}`] : [],
      hardhat: FORK_CHAIN ? [`deployments/${FORK_CHAIN}`] : [],
    },
  },
};
