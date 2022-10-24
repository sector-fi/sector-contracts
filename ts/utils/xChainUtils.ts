import { SectorCrossVault, SectorVault } from 'typechain';
import { getCompanionNetworks } from './network';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { getQuote, getRouteTransactionData } from './socketAPI';

const { utils } = ethers;
const { parseUnits, parseEther } = utils;

export const bridgeFunds = async (
  xVault: SectorCrossVault,
  toAddress: string,
  fromAsset: string,
  toAsset: string,
  fromChain: number,
  toChain: number,
  amount: number
) => {
  // Set Socket quote request params
  const uniqueRoutesPerBridge = true; // Set to true the best route for each bridge will be returned
  const sort = 'output'; // "output" | "gas" | "time"
  const singleTxOnly = true; // Set to true to look for a single transaction route

  // Get quote
  const quote = await getQuote(
    fromChain,
    fromAsset,
    toChain,
    toAsset,
    amount,
    toAddress,
    uniqueRoutesPerBridge,
    sort,
    singleTxOnly
  );

  console.log(
    fromChain,
    fromAsset,
    toChain,
    toAsset,
    amount,
    toAddress,
    uniqueRoutesPerBridge,
    sort,
    singleTxOnly
  );

  const routes = quote.result.routes;

  // loop routes
  let apiReturnData: any = {};
  for (const route of routes) {
    try {
      apiReturnData = await getRouteTransactionData(route);

      // console.log(apiReturnData);
      const request = {
        vaultAddr: toAddress,
        amount,
        allowanceTarget: apiReturnData.result.approvalData.allowanceTarget,
        registry: apiReturnData.result.txTarget,
        txData: apiReturnData.result.txData,
      };
      console.log(request);

      const tx = await xVault.depositIntoXVaults([request]);
      const res = await tx.wait();
      return res;
    } catch (e) {
      console.log(e);
      e;
      continue;
    }
    break;
  }
};

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
