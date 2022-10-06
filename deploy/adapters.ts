import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { network } from 'hardhat';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    // TODO: make sure the owner address is the one you wnat (set via .env)
    const { deployer, owner, guardian, manager, layerZeroEndpoint, multichainEndpoint } = await getNamedAccounts();
    const { deploy } = deployments;

    if (network.name === 'moonbean') {
        if (!multichainEndpoint) {
            throw new Error('multichainEndpoint not set');
        }
        const multichain = await deploy('MultichainAdapter', {
            contract: 'MultichainAdapter',
            from: deployer,
            args: [multichainEndpoint, owner, guardian, manager],
            skipIfAlreadyDeployed: false,
            log: true,
        })
        console.log('multichain deployed to', multichain.address);
    }
    else {
        if (!layerZeroEndpoint) {
            throw new Error('layerZeroEndpoint not set');
        }
        const layerZero = await deploy('LayerZeroAdapter', {
            contract: 'LayerZeroAdapter',
            from: deployer,
            args: [layerZeroEndpoint, owner, guardian, manager],
            skipIfAlreadyDeployed: false,
            log: true,
        });
        console.log('layerZero deployed to', layerZero.address);
    }
};

export default func;
func.tags = ['adapters'];
func.dependencies = ['XVault'];