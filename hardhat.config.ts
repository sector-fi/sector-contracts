import "@nomiclabs/hardhat-waffle";
import "hardhat-deploy";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import env from "dotenv";
import { subtask } from "hardhat/config";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
import "@nomiclabs/hardhat-etherscan";

Error.stackTraceLimit = Infinity;

// This skips the test comilation
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
  async (_, __, runSuper) => {
    const paths = await runSuper();
    return paths.filter((p) => !p.includes("src/tests"));
  }
);

// import 'hardhat-typechain'; // doesn't work rn
env.config();

const {
  DEPLOYER_KEY,
  MANAGER_KEY,
  INFURA_API_KEY,
  COIN_MARKET_CAP_API,
  SHOW_GAS,
  DEPLOYER,
  MANAGER,
  FORK_CHAIN,
  TEAM_1,
  TIMELOCK_ADMIN,
  SNOWTRACE_API_KEY,
  FTM_API_KEY,
  MOONRIVER_API_KEY,
  MOONBEAM_API_KEY,
} = process.env;

const keys = [DEPLOYER_KEY, MANAGER_KEY].filter((k) => k != null);

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  namedAccounts: {
    deployer: {
      default: DEPLOYER,
      // default: 'ledger://0x157875C30F83729Ce9c1E7A1568ec00250237862',
      hardhat: DEPLOYER,
      localhost: DEPLOYER,
    },
    owner: {
      default: 0,
      // default: 'ledger://0x157875C30F83729Ce9c1E7A1568ec00250237862',
      // hardhat: DEPLOYER,
    },
    managerProd: {
      default: "0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A",
    },
    manager: {
      default: "0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A",
      hardhat: MANAGER,
      localhost: MANAGER,
    },
    timelockAdmin: {
      default: TIMELOCK_ADMIN,
    },
    team1: {
      default: TEAM_1,
    },
    addr1: {
      default: 1,
    },
    addr2: {
      default: 2,
    },
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
      accounts: keys.length ? keys : undefined,
      tags: [FORK_CHAIN],
    },
    fantom: {
      url: "https://rpc.ftm.tools/",
      gasPrice: 700e9,
      chainId: 250,
      accounts: keys.length ? keys : undefined,
      tags: ["fantom"],
      verify: {
        etherscan: {
          apiKey: FTM_API_KEY,
          apiUrl: "https://api.ftmscan.com/",
        },
      },
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 27e9,
      chainId: 43114,
      accounts: keys.length ? keys : undefined,
      tags: ["avalanche"],
      verify: {
        etherscan: {
          apiKey: SNOWTRACE_API_KEY,
          apiUrl: "https://api.snowtrace.io/",
        },
      },
    },
    moonriver: {
      url: "https://rpc.api.moonriver.moonbeam.network",
      accounts: keys.length ? keys : undefined,
      chainId: 1285,
      gasPrice: 1.1e9,
      name: "moonriver",
      tags: ["moonriver"],
      verify: {
        etherscan: {
          apiKey: MOONRIVER_API_KEY,
        },
      },
    },
    moonbeam: {
      url: "https://rpc.api.moonbeam.network",
      accounts: keys.length ? keys : undefined,
      chainId: 1284,
      gasPrice: 101e9,
      name: "moonbeam",
      tags: ["moonbeam"],
      verify: {
        etherscan: {
          apiKey: MOONBEAM_API_KEY,
          apiUrl: "https://api-moonbeam.moonscan.io",
        },
      },
    },
    mainnet: {
      accounts: keys.length ? keys : undefined,
      url: "https://mainnet.infura.io/v3/" + INFURA_API_KEY,
      gasPrice: 2.1e9,
      chainId: 1,
    },
  },

  solidity: {
    compilers: [
      {
        version: "0.8.16",
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
    enabled: SHOW_GAS === "true",
    currency: "USD",
    gasPrice: 30,
    coinmarketcap: COIN_MARKET_CAP_API,
  },
  paths: {
    sources: "./src",
    cache: "./hh-cache",
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  etherscan: {
    apiKey: {
      moonbeam: MOONBEAM_API_KEY,
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
