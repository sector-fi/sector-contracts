// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { RedeemParams, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVault.sol";
import { AggregatorWEpochVaultCommon, AggregatorWEpochVault } from "./AggregatorWEpochVaultCommon.sol";

import "hardhat/console.sol";

contract AggregatorVaultTest is AggregatorWEpochVaultCommon {
	function setUp() public {
		setUpCommonTest();
	}

	function deployAggVault(bool takesNativeDeposit)
		public
		override
		returns (AggregatorWEpochVault)
	{
		return
			new AggregatorWEpochVault(
				underlying,
				"SECT_VAULT",
				"SECT_VAULT",
				takesNativeDeposit,
				3 days,
				type(uint256).max,
				AuthConfig(owner, guardian, manager),
				FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
			);
	}
}
