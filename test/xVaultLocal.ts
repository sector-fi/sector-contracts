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
import {
  SectorCrossVault,
  SectorVault,
  ERC20,
  LayerZeroPostman,
  ILayerZeroEndpoint,
} from '../typechain';
import { parseUnits, formatUnits, solidityPack } from 'ethers/lib/utils';
import { Web3Provider, ExternalProvider } from '@ethersproject/providers';
import fetch from 'node-fetch';

import chai from 'chai';
import { solidity } from 'ethereum-waffle';
import { expect } from 'chai';

chai.use(solidity);

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

  it('deposit into vaults', async function () {
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
      expect(tx?.status).to.be.eq(1);
    }
  });

  it('process deposits', async function () {
    const uAddr = await vault.underlying();
    const underlying = (await ethers.getContractAt(
      'IERC20',
      uAddr,
      l2Signer
    )) as ERC20;

    // const uBal = await underlying.balanceOf(vault.address);
    // expect(uBal).to.be.gt(0);

    // const tx = await vault.processIncomingXFunds();
    // const res = await tx.wait();
    // console.log(res);

    const l1VaultRecord = await xVault.addrBook(vault.address);

    const l1PostmanAddr = '0x75079AcAEB581e28040A049cA780e543F722eBdf';
    // const l1PostmanAddr = await xVault.postmanAddr(
    //   l1VaultRecord.postmanId,
    //   l1Id
    // );
    const l2PostmanAddr = await xVault.postmanAddr(
      l1VaultRecord.postmanId,
      l2Id
    );
    const l1Postman: LayerZeroPostman = await ethers.getContractAt(
      'LayerZeroPostman',
      l1PostmanAddr,
      l1Signer
    );

    const l2Postman: LayerZeroPostman = await ethers.getContractAt(
      'LayerZeroPostman',
      l2PostmanAddr,
      l2Signer
    );

    const l2endpointAddr = await l2Postman.endpoint();
    const l1endpointAddr = await l1Postman.endpoint();

    const l2endpoint: ILayerZeroEndpoint = await ethers.getContractAt(
      'ILayerZeroEndpoint',
      l2endpointAddr,
      l2Signer
    );

    const l1endpoint: ILayerZeroEndpoint = await ethers.getContractAt(
      'ILayerZeroEndpoint',
      l1endpointAddr,
      l1Signer
    );

    let ABI = [
      `function deliverMessage(tuple(uint256 value, address sender, address client, uint16 chainId) _msg, address _dstVautAddress, address _dstPostman, uint8 _messageType, uint16 _dstChainId, address _refundTo)`,
    ];
    let iface = new ethers.utils.Interface(ABI);
    const callData = iface.encodeFunctionData('deliverMessage', [
      ['9779427', xVault.address, ethers.constants.AddressZero, l1Id],
      vault.address,
      l2PostmanAddr,
      1,
      l2Id,
      owner,
    ]);

    {
      const tx = await xVault.addVault(vault.address, l2Id, 0, true);
      const res = await tx.wait();
      console.log(res);
    }

    // const tx = await l1Postman.deliverMessage(
    //   {
    //     value: '9779427',
    //     sender: xVault.address, // this gets overwritten
    //     client: ethers.constants.AddressZero,
    //     chainId: l1Id,
    //   },
    //   vault.address,
    //   // '0x8e3FFE1febd4034bDBB5b233cEcF7981849c583e',
    //   l2PostmanAddr,
    //   1,
    //   l2Id,
    //   owner
    // );

    // const tx = await xVault.emergencyAction(l1PostmanAddr, callData);
    return;

    const srcLzChain = 10;
    const destLzChain = 11;

    const path = solidityPack(
      ['address', 'address'],
      [l2PostmanAddr, l1PostmanAddr]
    );

    const chain = await l2endpoint.getChainId();
    console.log('endpoint chain', chain);
    const hasPayload = await l2endpoint.hasStoredPayload(srcLzChain, path);
    console.log('has payload', hasPayload);

    return;

    const xVaultShares = await vault.balanceOf(xVault.address);
    const xVaultBlanace = await vault.underlyingBalance(xVault.address);
    expect(xVaultShares).to.be.gt(0);
    // expect(xVaultBlanace).to.be.eq(uBal);
  });
});
