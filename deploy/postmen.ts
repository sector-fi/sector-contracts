import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { config } from 'hardhat';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    const { deployer, manager, layerZeroEndpoint, multichainEndpoint } = await getNamedAccounts();
    const { deploy, execute } = deployments;

    let test = config.networks

    console.log("Testing test", test);

    if (!multichainEndpoint) {
        throw new Error('multichainEndpoint not set');
    }

    if (!layerZeroEndpoint) {
        throw new Error('layerZeroEndpoint not set');
    }

    const postOffice = await deployments.get('postOffice');

    const layerZero = await deploy('LayerZeroPostman', {
        from: deployer,
        args: [layerZeroEndpoint, postOffice.address, manager],
        skipIfAlreadyDeployed: false,
        log: true,
    })
    console.log('LayerZero postman deployed to', layerZero.address);

    const multichain = await deploy('MultichainPostman', {
        from: deployer,
        args: [multichainEndpoint, postOffice.address],
        skipIfAlreadyDeployed: false,
        log: true,
    });
    console.log('Multichain postman deployed to', multichain.address);

    // TODO Execute setChain on layerZero and set the mapping chainId => lzChainId
};

export default func;
func.tags = ['postmen'];
func.dependencies = ['postOffice'];