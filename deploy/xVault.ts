import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { network } from 'hardhat';
import { getCompanionNetworks } from '../ts/utils';

// sector vault is allways an l1 deployment
const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  companionNetworks,
}: HardhatRuntimeEnvironment) {
  // xVault gets deployed on l1 companion network
  const { l1 } = await getCompanionNetworks();

  const {
    deployer,
    owner,
    guardian,
    manager,
    usdc,
  } = await l1.getNamedAccounts();
  const { deploy } = network.live
    ? companionNetworks.l1.deployments
    : deployments;

  let USDC = usdc;
  if (!usdc && !network.live) {
    const usdcMock = await deployments.get('USDCMock');
    USDC = usdcMock.address;
  }

  if (!USDC) throw new Error('missing usd address');

  const authConfig = [owner, guardian, manager];
  const feeConfig = [owner, 0, 0];

  const vault = await deploy('SectorXVault', {
    contract: 'SectorXVault',
    from: deployer,
    args: [USDC, 'XVault', 'XVLT', authConfig, feeConfig],
    skipIfAlreadyDeployed: false,
    log: true,
  });
  console.log('x-vault deplyed to', vault.address);
};

export default func;
func.tags = ['XVault'];
// Since USDC Mock is already setting the setup, we don't need to set it as a dependency
func.dependencies = ['Setup', 'USDCMock'];
