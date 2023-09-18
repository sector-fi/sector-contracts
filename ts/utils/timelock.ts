import { getNamedAccounts, ethers } from 'hardhat';
import type { TxOptions } from 'hardhat-deploy/types';
import { Contract, constants, utils } from 'ethers';
import { SectorTimelock } from 'typechain';

interface TxData {
  target: string;
  value: number;
  data: string;
  predecessor: string;
  salt: Uint8Array;
}

export const schedule = async (
  execute: any,
  options: TxOptions,
  contract: Contract,
  method: string,
  args: any[] = []
): Promise<TxData> => {
  const { deployer } = await getNamedAccounts();
  const timelock = (await ethers.getContract(
    'ScionTimelock',
    deployer
  )) as SectorTimelock;

  const delay = await timelock.getMinDelay();

  const tx: TxData = {
    value: 0,
    data: await contract.interface.encodeFunctionData(method, args),
    target: contract.address,
    predecessor: constants.HashZero,
    salt: utils.randomBytes(32),
  };

  await execute(
    'ScionTimelock',
    options,
    'schedule',
    tx.target,
    tx.value,
    tx.data,
    tx.predecessor,
    tx.salt,
    delay
  );
  return tx;
};

export const executeScheduled = async (
  execute: any,
  options: TxOptions,
  tx: TxData
): Promise<void> => {
  await execute(
    'ScionTimelock',
    options,
    'execute',
    tx.target,
    tx.value,
    tx.data,
    tx.predecessor,
    tx.salt
  );
};
