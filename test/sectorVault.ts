import {
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
import { parseUnits, formatUnits, solidityPack } from 'ethers/lib/utils';
import { Web3Provider, ExternalProvider } from '@ethersproject/providers';
import fetch from 'node-fetch';

import chai from 'chai';
import { solidity } from 'ethereum-waffle';
chai.use(solidity);
import { expect } from 'chai';

// @ts-ignore
global.fetch = fetch;

const setupTest = deployments.createFixture(async () => {
  await deployments.fixture(['XVault', 'SectorVault', 'AddVaults'], {
    keepExistingDeployments: true,
  });
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

    // sometimes we may use these to test against
    // await ethers.getContract('SectorXVault', l1Signer);

    xVault = new ethers.Contract(
      xVaultArtifact.address,
      xVaultArtifact.abi,
      l1Signer
    ) as SectorCrossVault;

    vault = await ethers.getContract('SectorVault', l2Signer);

    console.log('vault', vault.address);
    console.log('xVault', xVault.address);
  });

  it.skip('process deposits', async function () {
    const uAddr = await vault.underlying();
    const underlying = (await ethers.getContractAt(
      'IERC20',
      uAddr,
      l2Signer
    )) as ERC20;

    const uBal = await underlying.balanceOf(vault.address);
    expect(uBal).to.be.gt(0);

    const startXVaultShares = await vault.balanceOf(xVault.address);

    if (startXVaultShares.eq(0)) {
      const tx = await vault.processIncomingXFunds();
      const res = await tx.wait();
      // console.log(res);
      expect(res?.status).to.be.eq(1);
    }

    const xVaultShares = await vault.balanceOf(xVault.address);
    const xVaultBlanace = await vault.underlyingBalance(xVault.address);
    expect(xVaultShares).to.be.gt(0);
    expect(xVaultBlanace).to.be.closeTo(uBal, 1000);
  });

  it('finalizeHarvest', async function () {
    console.log(vault.address);
    const expectedTvl = await vault.underlyingBalance(xVault.address);
    const tx = await xVault.finalizeHarvest(expectedTvl, expectedTvl.div(100));
    const res = await tx.wait();
    expect(res?.status).to.be.eq(1);
  });
});
