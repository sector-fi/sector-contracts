import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { getDeployment } from '../ts/utils';

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
  deployments,
  companionNetworks,
}: HardhatRuntimeEnvironment) {
  const l1 = companionNetworks.l1;
  // live netwkrs don't need to specify l2
  const l2 = companionNetworks?.l2 || deployments;
  const { owner, layerZeroEndpoint } = await l2.getNamedAccounts();

  // hardhat network will allways execute on self
  const { execute: l1Execute } = network.live ? l1.deployments : deployments;
  const { execute: l2Execute } = network.live ? l2.deployments : deployments;

  const l1Chain = await l1.getChainId();
  const l2Chain = await l2.getChainId();
  const l1ChainName = network.config.companionNetworks?.l1;
  const l2ChainName = network.config.companionNetworks?.l2 || network.name;

  // decide which postman to use
  const l0PostmanId = 0;
  const multiChainPostmanId = 1;

  const postmanId =
    // @ts-ignore
    layerZeroEndpoint == null ? multiChainPostmanId : l0PostmanId;

  // getting this info via deployments on hardhat doesn't work for some reason
  const sectorVault = await getDeployment('SectorVault', l2ChainName);
  const xVault = await getDeployment('SectorXVault', l1ChainName);

  const localChain = network.live ? l1Chain : network.config.chainId;
  const localChainName: string = network.live ? l1ChainName : network.name;

  // setup own postman
  await l1Execute(
    'SectorXVault',
    { from: owner, log: true },
    'managePostman',
    postmanId,
    localChain,
    // XVault needs l1 postman
    await getPostmanAddr(postmanId, localChainName)
  );

  // setup own remote postman
  await l1Execute(
    'SectorXVault',
    { from: owner, log: true },
    'managePostman',
    postmanId,
    l2Chain,
    // XVault needs l1 postman
    await getPostmanAddr(postmanId, l2ChainName)
  );

  await l2Execute(
    'SectorVault',
    { from: owner, log: true },
    'managePostman',
    postmanId,
    l1Chain,
    // ChainVault needs own network postman
    await getPostmanAddr(postmanId, l1ChainName)
  );

  await l2Execute(
    'SectorVault',
    { from: owner, log: true },
    'managePostman',
    postmanId,
    l2Chain,
    // ChainVault needs own network postman
    await getPostmanAddr(postmanId, l2ChainName)
  );

  // add vaults
  await l1Execute(
    'SectorXVault',
    { from: owner, log: true },
    'addVault',
    sectorVault.address,
    l2Chain,
    postmanId,
    true
  );

  // add vaults
  await l2Execute(
    'SectorVault',
    { from: owner, log: true },
    'addVault',
    xVault.address,
    l1Chain,
    postmanId,
    true
  );
};

export default func;
func.tags = ['AddVaults'];
func.dependencies = ['Setup', 'Postmen', 'XVault', 'SectorVault'];

func.runAtTheEnd = true;

const getPostmanAddr = async (postmanId: number, chain: string) => {
  switch (postmanId) {
    case 0:
      return (await getDeployment('LayerZeroPostman', chain)).address;
    case 1:
      return (await getDeployment('MultichainPostman', chain)).address;
  }
};
