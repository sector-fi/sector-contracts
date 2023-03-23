// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { AggregatorVault, RedeemParams, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVault.sol";
import { AggregatorVaultCommon, AggregatorVault } from "./AggregatorVaultCommon.sol";

import "hardhat/console.sol";

contract AggregatorVaultTest is AggregatorVaultCommon {
	function setUp() public {
		setUpCommonTest();
	}

	function deployAggVault(bool takesNativeDeposit) public override returns (AggregatorVault) {
		return
			new AggregatorVault(
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
