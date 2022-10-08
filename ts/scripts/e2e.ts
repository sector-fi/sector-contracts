import {
  deployments,
  getUnnamedAccounts,
  companionNetworks,
  network,
} from 'hardhat';
const { execute } = deployments;
import { Web3Provider, ExternalProvider } from '@ethersproject/providers';

const main = async () => {
  const l1 = companionNetworks.l1;
  if (!l1) throw new Error('Missing l1 companion network');

  console.log('Current network:', network.config.chainId, `(${network.name})`);
  console.log('L1 network:', await l1.getChainId());

  // use these to execute or read on current network
  const { execute, read } = deployments;

  // use these to execute or read on l1 companion network
  const executeL1 = l1.deployments.execute;
  const readL1 = l1.deployments.read;
};

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
