import {
  ethers,
  config,
  network,
  deployments,
  companionNetworks,
  getNamedAccounts,
} from 'hardhat';
import { Contract, Signer } from 'ethers';
import fs from 'fs/promises';

const { parseUnits } = ethers.utils;

const { FORK_CHAIN = '' } = process.env;
export const chain = FORK_CHAIN;

export const forkBlock = {
  avalanche: 11348088,
  // fantom: 35896922,
  moonriver: 2189870,
  moonbeam: 1432482,
  // arbitrum: 31803223,
  // optimism: undefined,
};

export const setupAccount = async (address: string): Promise<Signer> => {
  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });

  await fundAccount(address, '10000');
  return (await ethers.getSigner(address)) as unknown as Signer;
};

export const updateOwner = async (
  contract: Contract,
  newOwner: string
): Promise<void> => {
  const owner = await contract.owner();
  if (owner == newOwner) return;
  const timelock = await ethers.getContract('ScionTimelock');
  if (timelock.address === owner) return;
  const ownerS = await setupAccount(owner);
  await contract.connect(ownerS).transferOwnership(newOwner);
};

export const fundAccount = async (
  address: string,
  eth: string
): Promise<void> => {
  await network.provider.send('hardhat_setBalance', [
    address,
    parseUnits(eth).toHexString().replace('0x0', '0x'),
  ]);
};

export const setMiningInterval = async (interval: number): Promise<void> => {
  await network.provider.send('evm_setAutomine', [interval === 0]);
  await network.provider.send('evm_setIntervalMining', [interval]);
};

export const forkNetwork = async (
  chain: string,
  blockNumber?: number
): Promise<void> => {
  // console.log('fork', config.networks[chain as string]?.url);
  await network.provider.request({
    method: 'hardhat_reset',
    params: [
      {
        forking: {
          // @ts-ignore
          jsonRpcUrl: config.networks[chain as string]?.url,
          blockNumber,
          enabled: true,
          ignoreUnknownTxType: true,
        },
      },
    ],
  });
};

export const fastForwardDays = async (days: number): Promise<void> => {
  await network.provider.send('evm_increaseTime', [days * 24 * 60 * 60]);
};

export const getDeployment = async (name: string, chain: string) => {
  if (chain == 'hardhat') return deployments.get(name);
  const filePath = `./deployments/${chain}/${name}.json`;
  const contractData: any = await fs.readFile(filePath, {
    encoding: 'utf8',
  });
  if (contractData == null)
    throw Error(`Missing deployment ${name} on ${chain}`);
  return JSON.parse(contractData);
};

export const getCompanionNetworks = async () => {
  const l1 = companionNetworks.l1;
  if (!l1) throw Error('Missing l1 companion network');
  // live networks don't need to specify l2
  const l2 = companionNetworks.l2 || {
    getNamedAccounts,
    deployments,
    getChainId: () => network.config.chainId,
  };

  const l1Id = await l1.getChainId();
  const l2Id = await l2.getChainId();

  const l1Name = network.config.companionNetworks?.l1;
  const l2Name = network.config.companionNetworks?.l2 || network.name;

  return { l1, l2, l1Id, l2Id, l1Name, l2Name };
};
