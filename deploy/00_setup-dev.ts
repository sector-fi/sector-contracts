import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { setupAccount, forkNetwork, chain, forkBlock } from '../ts/utils';

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
}: HardhatRuntimeEnvironment) {
  if (network.live) return;

  const { deployer, manager, guardian, owner } = await getNamedAccounts();

  await forkNetwork(chain, forkBlock[chain]);

  await setupAccount(owner);
  await setupAccount(guardian);
  await setupAccount(manager);
  await setupAccount(deployer);
};

export default func;
func.tags = ['Setup'];
