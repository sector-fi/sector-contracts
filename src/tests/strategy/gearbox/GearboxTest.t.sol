// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../../utils/SectorTest.sol";
import { IAddressProvider } from "interfaces/gearbox/IAddressProvider.sol";
import { IAccountFactoryGetters } from "interfaces/gearbox/IAccountFactoryGetters.sol";
import { ICreditFacade, ICreditManagerV2 } from "interfaces/gearbox/ICreditFacade.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IACL } from "interfaces/gearbox/IACL.sol";
import { IDegenNFT } from "interfaces/gearbox/IDegenNFT.sol";

import "hardhat/console.sol";

contract GearboxTest is SectorTest {
	string RPC_URL = vm.envString("ETH_RPC_URL");
	uint256 BLOCK = vm.envUint("ETH_BLOCK");

	IAddressProvider addressProvider = IAddressProvider(0xcF64698AFF7E5f27A11dff868AF228653ba53be0);
	IAccountFactoryGetters accFactory;
	ICreditFacade creditFacade = ICreditFacade(0xf6f4F24ae50206A07B8B32629AeB6cb1837d854F);
	ERC20 underlying;

	function setUp() public {
		uint256 fork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(fork);

		accFactory = IAccountFactoryGetters(addressProvider.getAccountFactory());

		// address configurator = IACL(addressProvider.getACL()).owner();
		// vm.prank(configurator);

		IDegenNFT degenNFT = IDegenNFT(creditFacade.degenNFT());
		address minter = degenNFT.minter();

		vm.prank(minter);
		degenNFT.mint(address(this), 1);

		underlying = ERC20(creditFacade.underlying());
		uint256 amount = 50000e18;
		deal(address(underlying), self, amount);

		ICreditManagerV2 creditManager = creditFacade.creditManager();
		underlying.approve(address(creditManager), amount);

		creditFacade.openCreditAccount(amount, self, 200, 0);
	}

	function testGrarbox() public {
		assertEq(creditFacade.hasOpenedCreditAccount(self), true);
	}
}
