import { getNamedAccounts, ethers } from 'hardhat';
import { Contract } from 'ethers';

export * from './network';
export * from './timelock';

export const waitFor = (delay: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, delay));
