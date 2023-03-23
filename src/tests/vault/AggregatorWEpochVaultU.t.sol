// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { AggregatorWEpochVaultU, RedeemParams, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorWEpochVaultU.sol";
import { SectorFactory, SectorBeacon } from "../../SectorFactory.sol";
import { AggregatorWEpochVaultCommon, AggregatorWEpochVault } from "./AggregatorWEpochVaultCommon.sol";

import "hardhat/console.sol";

contract AggregatorWEpochVaultTest is AggregatorWEpochVaultCommon {
	SectorFactory factory;
	string vaultType = "AggregatorVaultWEpoch";

	function setupFactory(string memory _vaultType) public {
		AggregatorWEpochVaultU vaultImp = new AggregatorWEpochVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory = new SectorFactory();
		factory.addVaultType(_vaultType, address(beacon));
	}

	function setUp() public {
		setupFactory(vaultType);
		setUpCommonTest();
	}

	function deployAggVault(bool takesNativeDeposit)
		public
		override
		returns (AggregatorWEpochVault)
	{
		bytes memory data = abi.encodeWithSelector(
			AggregatorWEpochVaultU.initialize.selector,
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			takesNativeDeposit,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);
		return AggregatorWEpochVault(payable(address(factory.deployVault(vaultType, data))));
	}
}
