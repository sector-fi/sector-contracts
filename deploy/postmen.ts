import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { config } from 'hardhat';

const func: DeployFunction = async function ({
  getNamedAccounts,
  deployments,
  network,
  companionNetworks,
}: HardhatRuntimeEnvironment) {
  const dep = !network.live
    ? [deployments]
    : [deployments, companionNetworks.l1.deployments];
  for (let i = 0; i < dep.length; i++) {
    const {
      deployer,
      manager,
      layerZeroEndpoint,
      multichainEndpoint,
    } = await getNamedAccounts();
    const { deploy, execute } = dep[i];

    const networks = config.networks;
    // console.log("NETWORKS", networks);

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

    const layerZero = await deploy('LayerZeroPostman', {
      from: deployer,
      args: [layerZeroEndpoint, chainIdMapping],
      skipIfAlreadyDeployed: false,
      log: true,
    });
    console.log('LayerZero postman deployed to', layerZero.address);

    // Just deploy if supportMultichain is set to true on hardhat network config.
    // @ts-ignore
    if (network.config.supportMultichain) {
      const multichain = await deploy('MultichainPostman', {
        from: deployer,
        args: [multichainEndpoint],
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
