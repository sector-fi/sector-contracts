import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { setupAccount } from "../utils";

const func: DeployFunction = async function ({
  deployments,
  getNamedAccounts,
  network,
  ethers,
}: HardhatRuntimeEnvironment) {
  const { deployer, manager, team1, timelockAdmin } = await getNamedAccounts();

  const { deploy, execute } = deployments;

  // To be updated after deployment
  const minDelay = 60 * 1; // 1m

  const proposers = [deployer, team1, timelockAdmin];
  const executors = [deployer, manager, team1];

  await deploy("ScionTimelock", {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: true,
    args: [minDelay, proposers, executors],
  });

  // if (network.live) return;
  // return;

  const timelock = await ethers.getContract("ScionTimelock", deployer);
  const vault = await ethers.getContract("USDC-Vault-0.2", deployer);
  const beacon = await ethers.getContract("UpgradeableBeacon", deployer);

  const proposerRole = await timelock.PROPOSER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();
  if (!network.live) {
    // await setupAccount(timelockAdmin);
    // await execute(
    //   'ScionTimelock',
    //   { from: timelockAdmin, log: true },
    //   'grantRole',
    //   proposerRole,
    //   deployer
    // );
    // await execute(
    //   'ScionTimelock',
    //   { from: timelockAdmin, log: true },
    //   'grantRole',
    //   executorRole,
    //   deployer
    // );
  }

  const vaultOwner = await vault.owner();
  const beaconOwner = await beacon.owner();

  if (vaultOwner !== timelock.address) {
    const isTeamManager = await vault.isManager(team1);
    if (!isTeamManager)
      await execute(
        "USDC-Vault-0.2",
        { from: deployer, log: true },
        "setManager",
        team1,
        true
      );
    console.log("set vault timelock");
    await execute(
      "USDC-Vault-0.2",
      { from: deployer, log: true },
      "transferOwnership",
      timelock.address
    );
  }

  if (beaconOwner !== timelock.address)
    await execute(
      "UpgradeableBeacon",
      { from: deployer, log: true },
      "transferOwnership",
      timelock.address
    );
};

export default func;
func.tags = ["Timelock"];
func.dependencies = ["Setup"];
