import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { network } from 'hardhat';
import { getCompanionNetworks } from '../ts/utils';

// sector vault is allways an l2 deployment
const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  companionNetworks,
}: HardhatRuntimeEnvironment) {
  const { l2 } = await getCompanionNetworks();

  const {
    deployer,
    owner,
    guardian,
    manager,
    usdc,
  } = await l2.getNamedAccounts();

  const { deploy } = deployments;

  let USDC = usdc;
  if (!network.live && !usdc) {
    const usdcMock = await deployments.get('USDCMock');
    USDC = usdcMock.address;
  }

  if (!USDC) throw new Error('missing usd address');

  const authConfig = [owner, guardian, manager];
  const feeConfig = [owner, 0, 0];

  const vault = await deploy('SectorVault', {
    from: deployer,
    args: [USDC, 'SectorVault', 'SVLT', authConfig, feeConfig],
    skipIfAlreadyDeployed: true,
    log: true,
  });
  console.log('sctorVault deplyed to', vault.address);
};

export default func;
func.tags = ['SectorVault'];
// Since USDC Mock is already setting the setup, we don't need to set it as a dependency
func.dependencies = ['Setup', 'USDCMock'];
