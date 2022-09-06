import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';
import { strategies } from '@sc1/common';

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
}: HardhatRuntimeEnvironment) {
  const { deployer } = await getNamedAccounts();

  const { execute } = deployments;

  const timelock = await ethers.getContract('ScionTimelock', deployer);

  for (let i = 0; i < strategies.length; i++) {
    const strat = strategies[i];
    // only deploy strategies that match the network tag
    if (!network.tags[strat.chain]) continue;
    const strategy = await ethers.getContract(strat.symbol, deployer);

    const stratOwner = await strategy.owner();

    if (stratOwner !== timelock.address) {
      await execute(
        strat.symbol,
        { from: deployer, log: true },
        'transferOwnership',
        timelock.address
      );
    }
  }
};

export default func;
func.tags = ['TimelockStrat'];
func.dependencies = ['Setup', 'Strategies'];
func.runAtTheEnd = true;
