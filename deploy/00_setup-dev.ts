import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { setupAccount } from '../utils';

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
}: HardhatRuntimeEnvironment) {
  if (network.live) return;

  const { deployer, manager } = await getNamedAccounts();

  await setupAccount(manager);
  await setupAccount(deployer);
};

export default func;
func.tags = ['Setup'];
