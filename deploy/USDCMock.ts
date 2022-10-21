import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from 'hardhat';

const func: DeployFunction = async function ({
    getNamedAccounts,
    deployments,
}: HardhatRuntimeEnvironment) {
    // TODO: make sure the owner address is the one you wnat (set via .env)
    const { deployer, usdc } = await getNamedAccounts();
    const { deploy } = deployments;

    if (!usdc) {
        const usdcMock = await deploy('USDCMock', {
            from: deployer,
            args: [ethers.utils.parseUnits('2000000', 6)],
            skipIfAlreadyDeployed: false,
            log: true,
        });
        console.log('usdc-mock deployed to', usdcMock.address);
    }
    else return;
};

export default func;
func.tags = ['USDCMock'];
func.dependencies = ['Setup'];