import { ethers } from 'hardhat';
import USDC from '../abi/USDC.json';
import { BigNumberish, Contract } from 'ethers';
import { parseUnits, formatUnits } from 'ethers/lib/utils';
import { setupAccount } from '.';

export const formatToken = async (tokenContract: Contract) => {
  const decimals = await tokenContract.decimals();
  return (input: BigNumberish) => formatUnits(input, decimals);
};

export const toStr = (input: any) => '' + input;

export const parseToken = async (tokenContract: Contract) => {
  const decimals = await tokenContract.decimals();
  return (input: number) => parseUnits(toStr(input), decimals);
};

export async function grantToken(
  contract: string,
  erc20Address: string,
  amount: number,
  whaleAddress: string
): Promise<void> {
  const signer = await setupAccount(whaleAddress);

  // USDC abi
  const ERC20 = await ethers.getContractAt(USDC, erc20Address);

  const format = await formatToken(ERC20);
  const parse = await parseToken(ERC20);

  await ERC20.connect(signer).transfer(contract, parse(amount));

  const balance = await ERC20.balanceOf(contract);
  console.log(`Now ${contract} has ${format(balance)}.`);
}
