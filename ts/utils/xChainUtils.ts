import { SectorCrossVault, SectorVault } from 'typechain';
import { getCompanionNetworks } from './network';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
const { utils } = ethers;
const { parseUnits, parseEther } = utils;

export const fundPostmen = async (
  xVault: SectorCrossVault,
  toAddress: string,
  l1Signer: Signer,
  l2Signer: Signer
) => {
  const { l1Id, l2Id } = await getCompanionNetworks();
  // src postman
  const l1VaultRecord = await xVault.addrBook(toAddress);
  const l1Postman = await xVault.postmanAddr(l1VaultRecord.postmanId, l1Id);
  const l2Postman = await xVault.postmanAddr(l1VaultRecord.postmanId, l2Id);

  // fund l1 postman
  const l1Balance = await l1Signer.provider!.getBalance(l1Postman);
  if (l1Balance.lt(parseUnits('.002'))) {
    const tx = await l1Signer.sendTransaction({
      to: l1Postman,
      value: parseEther('.004'),
    });
    await tx.wait();
  }

  // fund l2 postman
  const l2Balance = await l2Signer.provider!.getBalance(l2Postman);
  if (l2Balance.lt(parseUnits('.002'))) {
    const tx = await l2Signer.sendTransaction({
      to: l2Postman,
      value: parseEther('.004'),
    });
    await tx.wait();
  }
};
