import { ethers } from "hardhat";
import { getQuote, getRouteTransactionData } from '../utils';
import vaultAddr from "../vaultAddress.json";

async function main() {
    const vaultAddress = vaultAddr.eth;

    const [deployer] = await ethers.getSigners()
    const owner = deployer.address

    const erc20Addresses = {
        ethereum: {
            address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
            chainId: 1
        },
        arbitrium: {
            address: '0xff970a61a04b1ca14834a43f5de4533ebddb5cc8',
            chainId: 42161
        },
        optmism: {
            address: '0x7F5c764cBc14f9669B88837ca1490cCa17c31607',
            chainId: 10
        }
    }

    const VAULT = await ethers.getContractFactory("SectorCrossVault");
    const vault = VAULT.attach(vaultAddress);

    vault.on('bridgeAsset', async (_fromChainId, _toChainId, amount) => {

        console.log(`WE GOT AN EVENT on chain ${_fromChainId} to chain ${_toChainId} with value of ${amount}`)

        // Bridging Params fetched from users
        const fromChainId = _fromChainId;
        const toChainId = _toChainId;

        // get object with chainId === _fromChainId
        const fromChain = Object.values(erc20Addresses).find(chain => chain.chainId === fromChainId);
        const toChain = Object.values(erc20Addresses).find(chain => chain.chainId === toChainId);

        if (!fromChain || !toChain) {
            throw new Error('Chain not found');
        }

        // Set Socket quote request params
        const fromAssetAddress = fromChain.address;
        const toAssetAddress = toChain.address;
        const userAddress = vaultAddress; // The receiver address
        const uniqueRoutesPerBridge = true; // Set to true the best route for each bridge will be returned
        const sort = "output"; // "output" | "gas" | "time"
        const singleTxOnly = true; // Set to true to look for a single transaction route

        // Get quote
        const quote = await getQuote(
            fromChainId,
            fromAssetAddress,
            toChainId, toAssetAddress,
            amount, userAddress,
            uniqueRoutesPerBridge,
            sort, singleTxOnly
        );

        const route = quote.result.routes[1];

        // console.log("testing route: ", route);

        // Get transaction data
        const apiReturnData = await getRouteTransactionData(route);

        // Whitelists the receiver address on the destination chain
        await vault.whitelistSectorVault(toChainId, vaultAddress)

        const chainVaults = await vault.listChainVaults(42161);

        // Call to sendTokens on vault's contract
        try {
            const tx = await vault.sendTokens(
                apiReturnData.result.approvalData.allowanceTarget,
                apiReturnData.result.txTarget,
                userAddress,
                apiReturnData.result.approvalData.minimumApprovalAmount,
                toChainId,
                apiReturnData.result.txData,
            );
            // console.log(tx);
        } catch (error) {
            console.log(error);
        }
    })
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});