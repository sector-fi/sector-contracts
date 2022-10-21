import {
  getQuote,
  getRouteTransactionData,
  grantToken,
  forkNetwork,
  chain,
  forkBlock,
  waitFor,
  getDeployment,
} from '../ts/utils';
import {
  ethers,
  getNamedAccounts,
  deployments,
  network,
  companionNetworks,
} from 'hardhat';
import { SectorCrossVault, SectorVault, ERC20 } from '../typechain';
import { parseUnits, formatUnits } from 'ethers/lib/utils';
import { Web3Provider, ExternalProvider } from '@ethersproject/providers';
import fetch from 'node-fetch';

global.fetch = fetch;

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['XVault', 'SectorVault', 'AddVaults']);
});

describe('e2e x', function () {
  let xVault: SectorCrossVault;
  let vault: SectorVault;
  let owner;
  let l2Chain;
  let l1Chain;
  let l1Signer;
  let l2Signer;
  let l2ChainName;

  before(async () => {
    if (!network.live) await setupTest();
    ({ owner } = await getNamedAccounts());
    const l1 = companionNetworks.l1;
    const l2 = companionNetworks.l2;
    if (!l1) throw new Error('Missing l1 companion network');

    const l1Provider = new Web3Provider(
      (companionNetworks.l1.provider as unknown) as ExternalProvider
    );

    const l1ChainName = network.config.companionNetworks?.l1;
    l2ChainName = network.config.companionNetworks?.l2 || network.name;

    l1Signer = network.live
      ? new ethers.Wallet(network.config.accounts[0], l1Provider)
      : await ethers.getSigner(owner);
    l2Signer = await ethers.getSigner(owner);

    l2Chain = l2 ? await l2.getChainId() : network.config.chainId;
    l1Chain = await l1.getChainId();

    console.log('Current network:', l2Chain, `(${network.name})`);
    console.log('L1 network:', l1Chain);

    const xVaultArtifact = await getDeployment('SectorXVault', l1ChainName);
    const vaultArtifact = await getDeployment('SectorVault', l2ChainName);

    xVault = network.live
      ? (new ethers.Contract(
          xVaultArtifact.address,
          xVaultArtifact.abi,
          l1Signer
        ) as SectorCrossVault)
      : await ethers.getContract('SectorXVault', l1Signer);

    vault = await ethers.getContract('SectorVault', l2Signer);

    console.log('vault', vault.address);
    console.log('xVault', xVault.address);
  });

  it('e2e', async function () {
    const fromAsset = await xVault.underlying();
    const toAsset = '0x7F5c764cBc14f9669B88837ca1490cCa17c31607';
    // const toAsset = await vault.underlying();

    const amount = parseUnits('10', 6);

    const l1Underlying = (await ethers.getContractAt(
      'IERC20',
      fromAsset,
      l1Signer
    )) as ERC20;

    const balance = await xVault.underlyingBalance(owner);

    if (parseFloat(formatUnits(balance, 6)) < 5) {
      let tx = await l1Underlying.approve(xVault.address, amount);
      await tx.wait();
      tx = await xVault.deposit(amount, owner);
      await tx.wait();
    }

    const float = await xVault.floatAmnt();
    const toVault = await getDeployment('SectorVault', l2ChainName);

    const vaultRecord = await xVault.addrBook(toVault.address);
    const postman = await xVault.postmanAddr(
      vaultRecord.postmanId,
      network.config?.chainId?.toString()! /// TODO chainge for live test
    );

    // fund postman gas
    const vaultBalance = await xVault.provider.getBalance(postman);
    if (vaultBalance.lt(parseUnits('.002'))) {
      const tx = await l1Signer.sendTransaction({
        to: postman,
        value: ethers.utils.parseEther('.004'),
      });
      await tx.wait();
    }

    if (parseFloat(formatUnits(float, 6)) > 0) {
      const tx = await bridgeFunds(
        toVault.address,
        fromAsset,
        toAsset,
        l1Chain,
        l2Chain,
        amount.toNumber()
      );
      console.log('bridge tx', tx);
    }
  });

  const bridgeFunds = async (
    toAddress: string,
    fromAsset: string,
    toAsset: string,
    fromChain: number,
    toChain: number,
    amount: number
  ) => {
    // Set Socket quote request params
    const uniqueRoutesPerBridge = true; // Set to true the best route for each bridge will be returned
    const sort = 'output'; // "output" | "gas" | "time"
    const singleTxOnly = true; // Set to true to look for a single transaction route

    // Get quote
    const quote = await getQuote(
      fromChain,
      fromAsset,
      toChain,
      toAsset,
      amount,
      toAddress,
      uniqueRoutesPerBridge,
      sort,
      singleTxOnly
    );

    console.log(
      fromChain,
      fromAsset,
      toChain,
      toAsset,
      amount,
      toAddress,
      uniqueRoutesPerBridge,
      sort,
      singleTxOnly
    );

    const routes = quote.result.routes;

    // loop routes
    let apiReturnData: any = {};
    for (const route of routes) {
      try {
        apiReturnData = await getRouteTransactionData(route);

        // console.log(apiReturnData);
        const request = {
          vaultAddr: toAddress,
          amount,
          allowanceTarget: apiReturnData.result.approvalData.allowanceTarget,
          registry: apiReturnData.result.txTarget,
          txData: apiReturnData.result.txData,
        };
        console.log(request);

        const tx = await xVault.depositIntoXVaults([request]);
        const res = await tx.wait();
        console.log(res);
      } catch (e) {
        console.log(e);
        e;
        continue;
      }
      break;
    }
  };
});
