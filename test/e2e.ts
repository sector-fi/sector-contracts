import {
  getQuote,
  getRouteTransactionData,
  getDeployment,
  getCompanionNetworks,
  fundPostmen,
  bridgeFunds,
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
import { assert } from 'chai';

global.fetch = fetch;

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['XVault', 'SectorVault', 'AddVaults']);
});

describe('e2e x', function () {
  let xVault: SectorCrossVault;
  let vault: SectorVault;
  let owner;
  let l2Id;
  let l1Id;
  let l1Signer;
  let l2Signer;
  let l1Name, l2Name;
  let l1, l2;

  before(async () => {
    if (!network.live) await setupTest();
    ({ owner } = await getNamedAccounts());
    ({ l1, l2, l1Id, l2Id, l1Name, l2Name } = await getCompanionNetworks());

    const l1Provider = new Web3Provider(
      (companionNetworks.l1.provider as unknown) as ExternalProvider
    );

    l1Signer = network.live
      ? new ethers.Wallet(network.config.accounts[0], l1Provider)
      : await ethers.getSigner(owner);
    l2Signer = await ethers.getSigner(owner);

    console.log('Current network:', l2Id, l2Name);
    console.log('L1 network:', l1Id, l1Name);

    const xVaultArtifact = await getDeployment('SectorXVault', l1Name);
    const vaultArtifact = await getDeployment('SectorVault', l2Name);

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
    // const toAsset = '0x7F5c764cBc14f9669B88837ca1490cCa17c31607';
    const toAsset = await vault.underlying();

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

    // this is used in local hh test
    const toVault = await getDeployment('SectorVault', l2Name);
    await fundPostmen(xVault, toVault.address, l1Signer, l2Signer);

    const float = await xVault.floatAmnt();
    if (parseFloat(formatUnits(float, 6)) > 0) {
      const tx = await bridgeFunds(
        xVault,
        toVault.address,
        fromAsset,
        toAsset,
        l1Id,
        l2Id,
        amount.toNumber()
      );
      console.log('bridge tx', tx);
      assert(tx?.status == 1, 'Transaction seccess');
    }
  });
});
