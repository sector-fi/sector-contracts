import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';

const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  if (network.live) return;
  // TODO: make sure the owner address is the one you wnat (set via .env)
  const { deployer, usdc } = await getNamedAccounts();
  const { deploy } = deployments;

  // we can deploy multiple vaults with different name extensions -1, -2 etc
  if (!usdc) {
    const vault = await deploy('USDCMock', {
      from: deployer,
      args: [ethers.utils.parseUnits('2000000', 6)],
      skipIfAlreadyDeployed: false,
      log: true,
    });
    console.log('usdc-mock deployed to', vault.address);
  } else return;
};

export default func;
func.tags = ['USDCMock'];
func.dependencies = ['Setup'];
