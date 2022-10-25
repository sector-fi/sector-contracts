import {
  getDeployment,
  getCompanionNetworks,
  fundPostmen,
  bridgeFunds,
  debugPostman,
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
    // vault = await ethers.getContract('SectorVault', l2Signer);

    xVault = !network.live
      ? await ethers.getContract('SectorXVault', l1Signer)
      : (new ethers.Contract(
          xVaultArtifact.address,
          xVaultArtifact.abi,
          l1Signer
        ) as SectorCrossVault);

    vault = new ethers.Contract(
      vaultArtifact.address,
      vaultArtifact.abi,
      l2Signer
    ) as SectorVault;

    console.log('vault', vault.address);
    console.log('xVault', xVault.address);
  });

  it.skip('deposit into vaults', async function () {
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
        xVault.depositIntoXVaults,
        toVault.address,
        fromAsset,
        toAsset,
        l1Id,
        l2Id,
        amount.toString()
      );
      console.log('bridge tx', tx);
      expect(tx?.status).to.be.eq(1);
    }
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

  it.skip('harvestReq', async function () {
    await fundPostmen(xVault, vault.address, l1Signer, l2Signer);
    {
      const tx = await xVault.harvestVaults();
      const res = await tx.wait();
      expect(res?.status).to.be.eq(1);
    }
  });

  it.skip('finalizeHarvest', async function () {
    console.log(vault.address);

    const expectedTvl = await vault.underlyingBalance(xVault.address);
    // const expectedTvl = ethers.BigNumber.from('9664119');
    console.log(xVault.address);

    const {
      receivedAnswers,
      pendingAnswers,
      crossDepositValue,
    } = await xVault.harvestLedger();

    {
      const tx = await xVault.finalizeHarvest(
        expectedTvl,
        expectedTvl.div(100)
      );
      const res = await tx.wait();
      expect(res?.status).to.be.eq(1);
    }
  });

  it.skip('req withdraw', async function () {
    const shares = await xVault.balanceOf(owner);
    {
      const tx = await xVault['requestRedeem(uint256)'](shares);
      const res = await tx.wait();
      expect(res?.status).to.be.eq(1);
    }
    const totalAssets = await xVault.totalAssets();
    const pendingWithdraw = await xVault.pendingWithdraw();
    const withdrawShare = parseUnits('1').mul(pendingWithdraw).div(totalAssets);
    console.log('wShare', formatUnits(withdrawShare), withdrawShare.toString());

    await fundPostmen(xVault, vault.address, l1Signer, l2Signer);

    {
      const request = {
        vaultAddr: vault.address,
        amount: withdrawShare,
        fee: '0',
        allowanceTarget: ethers.constants.AddressZero,
        registry: ethers.constants.AddressZero,
        txData: [],
      };

      const tx = await xVault.withdrawFromXVaults([request]);
      const res = await tx.wait();
      expect(res?.status).to.be.eq(1);
    }
  });

  it('processXWithdraw', async function () {
    const toAsset = await xVault.underlying();
    const fromAsset = await vault.underlying();

    const amount = await vault.pendingWithdraw();
    console.log('pending withdraw', amount);

    const postman1 = await xVault.postmanAddr(0, l1Id);
    const postman2 = await vault.postmanAddr(0, l2Id);
    const path = solidityPack(['address', 'address'], [postman1, postman2]);
    console.log(path);

    await debugPostman(postman2, l2Signer, l1Name, path);

    //   const tx = await bridgeFunds(
    //     vault.processXWithdraw,
    //     xVault.address,
    //     fromAsset,
    //     toAsset,
    //     l2Id,
    //     l1Id,
    //     amount.toString()
    //   );
    //   expect(tx?.status).to.be.eq(1);
  });
});
