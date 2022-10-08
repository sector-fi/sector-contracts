import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    // TODO: make sure the owner address is the one you wnat (set via .env)
    const { deployer, owner, guardian, manager } = await getNamedAccounts();
    const { deploy } = deployments;






};

export default func;
func.tags = ['postOffice'];
func.dependencies = ['XVault'];