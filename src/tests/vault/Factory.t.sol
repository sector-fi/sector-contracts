// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { WETH } from "../mocks/WETH.sol";
import { ERC4626U, SectorBaseU as SectorBase, AggregatorVaultU, RedeemParams, DepositParams, IVaultStrategy, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVaultU.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { SectorFactory, SectorBeacon, OwnableTransfer } from "../../SectorFactory.sol";
import "../../SectorBeaconProxy.sol";

import "hardhat/console.sol";

contract FactoryTest is SectorTest {
	WETH underlying;

	AggregatorVaultU vault;

	string vaultType = "SectorVault";
	SectorFactory factory;

	function setUp() public {
		underlying = new WETH();

		AggregatorVaultU vaultImp = new AggregatorVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory = new SectorFactory();
		factory.addVaultType(vaultType, address(beacon));
	}

	function testAddVault() public {
		bytes memory data = abi.encodeWithSelector(
			AggregatorVaultU.initialize.selector,
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, 0e18, 0e18)
		);

		vault = AggregatorVaultU(payable(address(factory.deployVault(vaultType, data))));
		address vaultAddr = factory.getVaultById(vaultType, 0);
		assertEq(address(vaultAddr), address(vault));
		assertEq(factory.totalVaults(), 1);
	}

	function testAddNewType() public {
		string memory newType = "NewType";
		AggregatorVaultU vaultImp = new AggregatorVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory.addVaultType(newType, address(beacon));

		bytes memory data = abi.encodeWithSelector(
			AggregatorVaultU.initialize.selector,
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, 0e18, 0e18)
		);

		vault = AggregatorVaultU(payable(address(factory.deployVault(newType, data))));
		address vaultAddr = factory.getVaultById(newType, 0);
		assertEq(address(vaultAddr), address(vault));
		assertEq(factory.totalVaultTypes(), 2);
	}

	function testFactoryOwnershipTransfer() public {
		address newOwner = address(0x1);

		vm.prank(newOwner);
		vm.expectRevert("Ownable: caller is not the owner");
		factory.transferOwnership(newOwner);

		factory.transferOwnership(newOwner);

		// not transferred yet
		assertEq(factory.owner(), self);

		vm.expectRevert(OwnableTransfer.OnlyPendingOwner.selector);
		factory.acceptOwnership();

		vm.prank(newOwner);
		factory.acceptOwnership();
		assertEq(factory.owner(), newOwner);
	}

	function testBeaconOwnershipTransfer() public {
		AggregatorVaultU vaultImp = new AggregatorVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));

		address newOwner = address(0x1);

		vm.prank(newOwner);
		vm.expectRevert("Ownable: caller is not the owner");
		beacon.transferOwnership(newOwner);

		beacon.transferOwnership(newOwner);

		// not transferred yet
		assertEq(beacon.owner(), self);

		vm.expectRevert(OwnableTransfer.OnlyPendingOwner.selector);
		beacon.acceptOwnership();

		vm.prank(newOwner);
		beacon.acceptOwnership();
		assertEq(beacon.owner(), newOwner);
	}
}
