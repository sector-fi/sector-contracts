import hre from "hardhat";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { forkNetwork, setupAccount, grantToken, parseToken } from "../utils";
import fs from 'fs';

async function deployBank(
  owner: string,
  guardian: string,
  manager: string,
  treasury: string): Promise<Contract> {
  const BANK = await ethers.getContractFactory("Bank");

  const bank = await BANK.deploy('https://game.example/api/item/{id}.json', owner, guardian, manager, treasury);
  await bank.deployed()

  return bank;
}

async function deployVault(
  tokenAddress: string,
  bankAddress: string,
  managementFee: number,
  owner: string,
  guardian: string,
  manager: string): Promise<Contract> {

  managementFee;

  const VAULT = await ethers.getContractFactory("SectorCrossVault");
  const vault = await VAULT.deploy(tokenAddress, bankAddress, owner, guardian, manager);
  await vault.deployed();

  return vault;
}

async function main() {

  await forkNetwork('mainnet');

  const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48' // USDC ETHEREUM

  const [deployer] = await ethers.getSigners()
  const owner = deployer.address

  await setupAccount(owner)

  let vaults: Array<Contract> = []

  const bank = await deployBank(owner, owner, owner, owner)
  const vault = await deployVault(USDC, bank.address, 0, owner, owner, owner)
  vaults.push(vault)

  await bank.addPool({
    vault: vault.address,
    id: 0,
    managementFee: 0,
    decimals: 18,
    exists: true
  })

  console.log(`Bank deployed at ${bank.address}`);
  console.log(`Vault deployed at ${vault.address}`);

  // Write vault address to a file
  let jsonContent = JSON.stringify({
    eth: vaults[0].address,
  });
  fs.writeFile("vaultAddress.json", jsonContent, 'utf8', function (err) {
    if (err) {
      console.log("An error occured while writing JSON Object to File.");
      return console.log(err);
    }
  });

  const whaleAddress = '0x0A59649758aa4d66E25f08Dd01271e891fe52199'

  // Grant tokens to vault
  await grantToken(
    vaults[0].address,
    USDC,
    5000,
    whaleAddress
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});