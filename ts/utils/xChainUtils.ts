import {
  ILayerZeroEndpoint,
  LayerZeroPostman,
  SectorCrossVault,
  SectorVault,
} from 'typechain';
import { getCompanionNetworks } from './network';
import { ethers, config } from 'hardhat';
import { Signer } from 'ethers';
import { getQuote, getRouteTransactionData } from './socketAPI';

const { utils, BigNumber } = ethers;
const { parseUnits, parseEther } = utils;

export const bridgeFunds = async (
  bridgeTx:
    | SectorCrossVault['depositIntoXVaults']
    | SectorVault['processXWithdraw'],
  toAddress: string,
  fromAsset: string,
  toAsset: string,
  fromChain: number,
  toChain: number,
  amount: string
) => {
  // Set Socket quote request params
  const uniqueRoutesPerBridge = true; // Set to true the best route for each bridge will be returned
  const sort = 'output'; // "output" | "gas" | "time"
  const singleTxOnly = true; // Set to true to look for a single transaction route

  const args = [
    fromChain,
    fromAsset,
    toChain,
    toAsset,
    amount,
    toAddress,
    uniqueRoutesPerBridge,
    sort,
    singleTxOnly,
  ] as const;
  console.log(args);

  // Get quote
  const quote = await getQuote(...args);
  console.log(quote);

  const routes = quote.result.routes;
  routes.forEach((r) => console.log(r.toAmount));

  // loop routes
  let apiReturnData: any = {};
  for (const route of routes) {
    try {
      apiReturnData = await getRouteTransactionData(route);

      const fee = BigNumber.from(amount).sub(BigNumber.from(route.toAmount));
      console.log('Fee', fee.toString());

      const request = {
        vaultAddr: toAddress,
        amount,
        fee,
        allowanceTarget: apiReturnData.result.approvalData.allowanceTarget,
        registry: apiReturnData.result.txTarget,
        txData: apiReturnData.result.txData,
      };

      const tx = await bridgeTx([request]);
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

export const debugPostman = async (postmanAddr, signer, chainName, path) => {
  const postman: LayerZeroPostman = await ethers.getContractAt(
    'LayerZeroPostman',
    postmanAddr,
    signer
  );

  const enpointAddr = await postman.endpoint();

  const endpoint: ILayerZeroEndpoint = await ethers.getContractAt(
    'ILayerZeroEndpoint',
    enpointAddr,
    signer
  );

  // @ts-ignore
  const chainId = config.networks[chainName].layerZeroId;
  console.log(chainId);

  const hasPayload = await endpoint.hasStoredPayload(chainId, path);
  console.log('has payload', hasPayload);
  if (!hasPayload) return;

  // have to get payload somehow

  // const tx = await endpoint.retryPayload(chainId, path, payload.payloadHash);
  // const res = await tx.wait();
  // console.log(res);
};
