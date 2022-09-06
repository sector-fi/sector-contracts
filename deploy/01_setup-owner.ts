import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { updateOwner } from "../utils";
import { ethers } from "hardhat";

const func: DeployFunction = async function ({
  getNamedAccounts,
  network,
}: HardhatRuntimeEnvironment) {
  if (network.live) return;

  const { deployer, manager } = await getNamedAccounts();

  const vaultFactory = await ethers.getContract("ScionVaultFactory", deployer);
  await updateOwner(vaultFactory, deployer);

  // set owner of contracts to curren DEPLOYER addrs
  const vault = await ethers.getContract("USDC-Vault-0.2", deployer);
  await updateOwner(vault, deployer);
  const isManager = await vault.isManager(manager);
};

export default func;
func.tags = ["DevOwner"];
func.dependencies = ["Strategies"];
