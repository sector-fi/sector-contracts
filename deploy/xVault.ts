import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const USDC = '0x5FfbaC75EFc9547FBc822166feD19B05Cd5890bb';

// Goerli
const layerZeroEndpointGoerli = '0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23';
// Fuji
const layerZeroEndpointFuji = '0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706';

const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
}: HardhatRuntimeEnvironment) {
  // TODO: make sure the owner address is the one you wnat (set via .env)
  const { deployer, owner } = await getNamedAccounts();
  const { deploy } = deployments;

  // we can deploy multiple vaults with different name extensions -1, -2 etc
  const vault = await deploy('SectorCrossVault-0', {
    contract: 'SectorCrossVault',
    from: deployer,
    args: [USDC, 'PichaToken', 'PTK', owner, owner, owner, owner, 0],
    skipIfAlreadyDeployed: false,
    log: true,
  });
  console.log('x-vault deplyed to', vault.address);
};

export default func;
func.tags = ['XVault'];
func.dependencies = ['Setup'];
