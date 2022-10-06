import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const ownerAddress = "0x60b4e7742328eF121ff4f5df513ca1d4e3ba2E04"
const USDC = "0x5FfbaC75EFc9547FBc822166feD19B05Cd5890bb"
// Goerli
const layerZeroEndpointGoerli = "0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23"
// Fuji
const layerZeroEndpointFuji = "0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706"

const func: DeployFunction = async function ({
    getNamedAccounts,
    network,
}: HardhatRuntimeEnvironment) {
    // Get contract's factory

    const { deployer, manager, guardian, owner, usdc } = await getNamedAccounts();
    // Change deploy account to deployer on ethers?

    // Add isTestNet to all networks
    // check istest and deploy ERC20 if necessary
    // And proper put addres below
    const usdcAddress = usdc[network.name];

    const VAULT = await ethers.getContractFactory("SectorCrossVault");

    const vault = await VAULT.deploy(usdcAddress, 'XVaultShare', 'XVS', owner, guardian, manager, owner, 0);
    await vault.deployed();


    console.log("lockRewards deployed to:", vault.address);
};

export default func;
func.tags = ['CrossVault'];