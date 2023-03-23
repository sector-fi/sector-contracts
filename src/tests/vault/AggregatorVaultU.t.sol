// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { AggregatorVaultU, RedeemParams, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVaultU.sol";
import { SectorFactory, SectorBeacon } from "../../SectorFactory.sol";
import { AggregatorVaultCommon, AggregatorVault } from "./AggregatorVaultCommon.sol";

import "hardhat/console.sol";

contract AggregatorVaultUTest is AggregatorVaultCommon {
	SectorFactory factory;
	string vaultType = "AggregatorVault";

	function setupFactory(string memory _vaultType) public {
		AggregatorVaultU vaultImp = new AggregatorVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory = new SectorFactory();
		factory.addVaultType(_vaultType, address(beacon));
	}

	function setUp() public {
		setupFactory(vaultType);
		setUpCommonTest();
	}

	function deployAggVault(bool takesNativeDeposit) public override returns (AggregatorVault) {
		bytes memory data = abi.encodeWithSelector(
			AggregatorVaultU.initialize.selector,
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			takesNativeDeposit,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);
		return AggregatorVault(payable(address(factory.deployVault(vaultType, data))));
	}
}
