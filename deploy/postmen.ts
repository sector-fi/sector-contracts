import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { config } from 'hardhat';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
    network
}: HardhatRuntimeEnvironment) {
    const { deployer, manager, layerZeroEndpoint, multichainEndpoint } = await getNamedAccounts();
    const { deploy } = deployments;

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
        if (value.layerZeroId) {
            chainIdMapping.push([value.chainId, value.layerZeroId]);
        }
    }

    const layerZero = await deploy('LayerZeroPostman', {
        from: deployer,
        args: [layerZeroEndpoint, chainIdMapping],
        skipIfAlreadyDeployed: false,
        log: true,
    })
    console.log('LayerZero postman deployed to', layerZero.address);

    // Just deploy if supportMultichain is set to true on hardhat network config.
    if (network.config.supportMultichain) {
        const multichain = await deploy('MultichainPostman', {
            from: deployer,
            args: [multichainEndpoint, manager],
            skipIfAlreadyDeployed: false,
            log: true,
        });
        console.log('Multichain postman deployed to', multichain.address);
    }
    else console.log(`${network.name} does not support multichain`);

};

export default func;
func.tags = ['Postmen'];
func.dependencies = ['Setup'];