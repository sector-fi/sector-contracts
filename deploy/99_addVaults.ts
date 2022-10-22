import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getDeployment, getCompanionNetworks } from '../ts/utils';
import { network } from 'hardhat';

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
  deployments,
  companionNetworks,
}: HardhatRuntimeEnvironment) {
  const { l1, l2, l1Id, l2Id, l1Name, l2Name } = await getCompanionNetworks();

  const { owner, layerZeroEndpoint } = await l2.getNamedAccounts();

  // hardhat network should allways execute on self
  const { execute: l1Execute } = network.live ? l1.deployments : deployments;
  const { execute: l2Execute } = network.live ? l2.deployments : deployments;

  const { read: l1Read } = network.live ? l1.deployments : deployments;
  const { read: l2Read } = network.live ? l2.deployments : deployments;

  // decide which postman to use
  const l0PostmanId = 0;
  const multiChainPostmanId = 1;

  const postmanId =
    // @ts-ignore
    layerZeroEndpoint == null ? multiChainPostmanId : l0PostmanId;

  // getting this info via deployments on hardhat doesn't work for some reason
  const sectorVault = await getDeployment('SectorVault', l2Name);
  const xVault = await getDeployment('SectorXVault', l1Name);

  // setup own postman
  await configPostman(
    'SectorXVault',
    l1Execute,
    l1Read,
    owner,
    postmanId,
    l1Name,
    l1Id
  );

  await configPostman(
    'SectorXVault',
    l1Execute,
    l1Read,
    owner,
    postmanId,
    l2Name,
    l2Id
  );

  await configPostman(
    'SectorVault',
    l2Execute,
    l2Read,
    owner,
    postmanId,
    l1Name,
    l1Id
  );

  await configPostman(
    'SectorVault',
    l2Execute,
    l2Read,
    owner,
    postmanId,
    l2Name,
    l2Id
  );

  // add vaults
  const { allowed: sectorVaultExists } = await l1Read(
    'SectorXVault',
    'addrBook',
    sectorVault.address
  );
  if (!sectorVaultExists)
    await l1Execute(
      'SectorXVault',
      { from: owner, log: true },
      'addVault',
      sectorVault.address,
      l2Id,
      postmanId,
      true
    );

  let { allowed: SectorXVaultExists } = await l2Read(
    'SectorVault',
    'addrBook',
    xVault.address
  );
  if (!SectorXVaultExists)
    await l2Execute(
      'SectorVault',
      { from: owner, log: true },
      'addVault',
      xVault.address,
      l1Id,
      postmanId,
      true
    );
};

export default func;
func.tags = ['AddVaults'];
func.dependencies = ['Setup', 'Postmen', 'XVault', 'SectorVault'];
func.runAtTheEnd = true;

const configPostman = async (
  vaultName,
  execute,
  read,
  owner,
  postmanId,
  chainName,
  chainId
) => {
  const deployedPostman = await getPostmanAddr(postmanId, chainName);
  const currentPostman = await read(
    vaultName,
    'postmanAddr',
    postmanId,
    chainId
  );
  if (deployedPostman !== currentPostman)
    await execute(
      vaultName,
      { from: owner, log: true },
      'managePostman',
      postmanId,
      chainId,
      deployedPostman
    );
};

const getPostmanAddr = async (postmanId: number, chain: string) => {
  switch (postmanId) {
    case 0:
      return (await getDeployment('LayerZeroPostman', chain)).address;
    case 1:
      return (await getDeployment('MultichainPostman', chain)).address;
  }
};
