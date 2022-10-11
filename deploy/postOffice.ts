import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    // TODO: make sure the owner address is the one you wnat (set via .env)
    const { deployer } = await getNamedAccounts();
    const { deploy } = deployments;

    const postOffice = await deploy('PostOffice', {
        from: deployer,
        args: [],
        skipIfAlreadyDeployed: false,
        log: true,
    })

    console.log('PostOffice deployed to', postOffice.address);
};

export default func;
func.tags = ['postOffice'];
func.dependencies = ['XVault'];