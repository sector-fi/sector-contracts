// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { WETH } from "../mocks/WETH.sol";
import { ERC4626U, SectorBaseU as SectorBase, AggregatorVaultU, RedeemParams, DepositParams, IVaultStrategy, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVaultU.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { SectorFactory, UpgradeableBeacon } from "../../SectorFactory.sol";
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
		UpgradeableBeacon beacon = new UpgradeableBeacon(address(vaultImp));
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
	}

	function testAddNewType() public {
		string memory newType = "NewType";
		AggregatorVaultU vaultImp = new AggregatorVaultU();
		UpgradeableBeacon beacon = new UpgradeableBeacon(address(vaultImp));
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
	}
}
