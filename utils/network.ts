import { ethers, config, network } from "hardhat";
import { Contract, Signer } from "ethers";

const { parseUnits } = ethers.utils;

const { FORK_CHAIN = "" } = process.env;
export const chain = FORK_CHAIN;

export const forkBlock = {
  avalanche: 11348088,
  // fantom: 35896922,
  moonriver: 2189870,
  moonbeam: 1432482,
};

export const setupAccount = async (address: string): Promise<Signer> => {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });

  await fundAccount(address, "10000");
  return await ethers.getSigner(address);
};

export const updateOwner = async (
  contract: Contract,
  newOwner: string
): Promise<void> => {
  const owner = await contract.owner();
  if (owner == newOwner) return;
  const timelock = await ethers.getContract("ScionTimelock");
  if (timelock.address === owner) return;
  const ownerS = await setupAccount(owner);
  await contract.connect(ownerS).transferOwnership(newOwner);
};

export const fundAccount = async (
  address: string,
  eth: string
): Promise<void> => {
  await network.provider.send("hardhat_setBalance", [
    address,
    parseUnits(eth).toHexString().replace("0x0", "0x"),
  ]);
};

export const setMiningInterval = async (interval: number): Promise<void> => {
  await network.provider.send("evm_setAutomine", [interval === 0]);
  await network.provider.send("evm_setIntervalMining", [interval]);
};

export const forkNetwork = async (
  chain: string,
  blockNumber?: number
): Promise<void> => {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          // @ts-ignore
          jsonRpcUrl: config.networks[chain as string]?.url,
          blockNumber,
        },
      },
    ],
  });
};

export const fastForwardDays = async (days: number): Promise<void> => {
  await network.provider.send("evm_increaseTime", [days * 24 * 60 * 60]);
};
