import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    // TODO: make sure the owner address is the one you wnat (set via .env)
    const { deployer, owner, guardian, manager, layerZeroEndpoint, multichainEndpoint } = await getNamedAccounts();
    const { deploy } = deployments;

    // if there is no layerZeroEndpoint or MultichainEndpoint, throw an error
    if (!layerZeroEndpoint || !multichainEndpoint) {
        throw new Error('layerZeroEndpoint or MultichainEndpoint not set');
    }

    const layerZero = await deploy('LayerZeroAdapter', {
        contract: 'LayerZeroAdapter',
        from: deployer,
        args: [layerZeroEndpoint, owner, guardian, manager],
        skipIfAlreadyDeployed: false,
        log: true,
    });
    console.log('layerZero deployed to', layerZero.address);

    const multichain = await deploy('MultichainAdapter', {
        contract: 'MultichainAdapter',
        from: deployer,
        args: [multichainEndpoint, owner, guardian, manager],
        skipIfAlreadyDeployed: false,
        log: true,
    })
    console.log('multichain deployed to', multichain.address);
};

export default func;
func.tags = ['adapters'];
func.dependencies = ['XVault'];