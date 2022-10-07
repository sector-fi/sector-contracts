import {
  getQuote,
  getRouteTransactionData,
  grantToken,
  forkNetwork,
  chain,
  forkBlock,
  waitFor,
} from '../ts/utils';
import { ethers, getNamedAccounts, deployments, network } from 'hardhat';
import { SectorCrossVault } from '../typechain';

// TODO orgainze these into a config file
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'; // USDC ETHEREUM

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['XVault']);
  const { deployer } = await getNamedAccounts();

  // this contract will be grabbed form the deployments generated via the deployment fixture
  // above, we can grab different contracts via the name we saved them as
  const vault: SectorCrossVault = await ethers.getContract(
    'SectorCrossVault-0',
    deployer
  );

  // TODO: this can be moved to setup deployment
  const whaleAddress = '0x0A59649758aa4d66E25f08Dd01271e891fe52199';

  // Grant tokens to vault
  await grantToken(vault.address, USDC, 5000, whaleAddress);
  return vault;
});

describe('events', function () {
  let vault: SectorCrossVault;
  before(async () => {
    // fork chain is set via .evn FORK_CHAIN param
    await forkNetwork(chain, forkBlock[chain]);
    vault = await setupTest();
  });
  it('should send events', async function () {
    listenToEvents(vault);
    const fromChainId = 1;
    const toChainId = 42161;
    const amount = 21000001;

    // TODO update this method
    await vault.bridgeAssets(fromChainId, toChainId, amount);
    // wait a little bit for events to propagate
    waitFor(2000);
  });
});

async function listenToEvents(vault: SectorCrossVault) {
  const erc20Addresses = {
    ethereum: {
      address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
      chainId: 1,
    },
    arbitrium: {
      address: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8',
      chainId: 42161,
    },
    optmism: {
      address: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
      chainId: 10,
    },
  };

  vault.on('bridgeAsset', async (_fromChainId, _toChainId, amount) => {
    console.log(
      `WE GOT AN EVENT on chain ${_fromChainId} to chain ${_toChainId} with value of ${amount}`
    );

    // Bridging Params fetched from users
    const fromChainId = _fromChainId;
    const toChainId = _toChainId;

    // get object with chainId === _fromChainId
    const fromChain = Object.values(erc20Addresses).find(
      (chain) => chain.chainId === fromChainId
    );
    const toChain = Object.values(erc20Addresses).find(
      (chain) => chain.chainId === toChainId
    );

    if (!fromChain || !toChain) {
      throw new Error('Chain not found');
    }

    // Set Socket quote request params
    const fromAssetAddress = fromChain.address;
    const toAssetAddress = toChain.address;
    const userAddress = vault.address; // The receiver address
    const uniqueRoutesPerBridge = true; // Set to true the best route for each bridge will be returned
    const sort = 'output'; // "output" | "gas" | "time"
    const singleTxOnly = true; // Set to true to look for a single transaction route

    // Get quote
    const quote = await getQuote(
      fromChainId,
      fromAssetAddress,
      toChainId,
      toAssetAddress,
      amount,
      userAddress,
      uniqueRoutesPerBridge,
      sort,
      singleTxOnly
    );

    const routes = quote.result.routes;

    // Whitelists the receiver address on the destination chain
    // TODO: re-enable this method
    await vault.whitelistSectorVault(toChainId, vault.address);

    // loop routes
    let apiReturnData: any = {};
    for (const route of routes) {
      try {
        apiReturnData = await getRouteTransactionData(route);
        await vault.sendTokens(
          apiReturnData.result.approvalData.allowanceTarget,
          apiReturnData.result.txTarget,
          userAddress,
          apiReturnData.result.approvalData.minimumApprovalAmount,
          toChainId,
          apiReturnData.result.txData
        );
      } catch (e) {
        e;
        continue;
      }
      break;
    }
  });
}
