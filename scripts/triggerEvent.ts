import { ethers } from "hardhat";
import vaultAddr from "../vaultAddress.json";

export async function triggerBridge(vaultAddress: string, fromChainId: number, toChainId: number, amount: number) {
  const VAULT = await ethers.getContractFactory("SectorVault");
  const vault = VAULT.attach(vaultAddress);

  // chainId, amount
  await vault.bridgeAssets(fromChainId, toChainId, amount);
}

async function main() {
  const vault = vaultAddr.eth;
  const fromChainId = 1;
  const toChainId = 42161;
  const amount = 21000001;

  await triggerBridge(vault, fromChainId, toChainId, amount);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});