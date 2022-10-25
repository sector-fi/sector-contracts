import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { config } from 'hardhat';
import { getCompanionNetworks } from '../ts/utils';

const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  network,
}: HardhatRuntimeEnvironment) {
  const { l1, l2 } = await getCompanionNetworks();

  const chains = !network.live ? [l1] : [l1, l2];
  for (let i = 0; i < chains.length; i++) {
    const c = chains[i];
    const {
      deployer,
      manager,
      layerZeroEndpoint,
      multichainEndpoint,
    } = await c.getNamedAccounts();
    // if not on live network, only current chain deployments
    const deploy = !network.live ? deployments.deploy : c.deployments.deploy;

    const networks = config.networks;

    if (!multichainEndpoint) {
      throw new Error('multichainEndpoint not set');
    }

    if (!layerZeroEndpoint) {
      throw new Error('layerZeroEndpoint not set');
    }

    // Loop all networks on hardhat config and set layzerZero chainId to the corresponding network.
    let chainIdMapping: Array<any> = [];

    for (let [key, value] of Object.entries(networks)) {
      // @ts-ignore
      if (value.layerZeroId) {
        // @ts-ignore
        chainIdMapping.push([value.chainId, value.layerZeroId]);
      }
    }
    // console.log(chainIdMapping)

    const layerZero = await deploy('LayerZeroPostman', {
      from: deployer,
      args: [layerZeroEndpoint, chainIdMapping, manager],
      skipIfAlreadyDeployed: false,
      log: true,
    });
    console.log('LayerZero postman deployed to', layerZero.address);

    // Just deploy if supportMultichain is set to true on hardhat network config.
    // @ts-ignore
    if (network.config.supportMultichain) {
      const multichain = await deploy('MultichainPostman', {
        from: deployer,
        args: [multichainEndpoint, manager],
        skipIfAlreadyDeployed: false,
        log: true,
      });
      console.log('Multichain postman deployed to', multichain.address);
    } else console.log(`${network.name} does not support multichain`);
  }
};

export default func;
func.tags = ['Postmen'];
func.dependencies = ['Setup'];
