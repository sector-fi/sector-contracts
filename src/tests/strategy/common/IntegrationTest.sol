// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../../utils/SectorTest.sol";
import { SCYStratUtils, IERC20 } from "./SCYStratUtils.sol";
import { UniswapMixin } from "./UniswapMixin.sol";
import { ERC4626, SectorBase, AggregatorVault, RedeemParams, DepositParams, IVaultStrategy, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVault.sol";
import { SCYVaultUtils } from "../../vault/SCYVaultUtils.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "hardhat/console.sol";

// These test run for all strategies
abstract contract IntegrationTest is SectorTest, SCYStratUtils {
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 DEAFAULT_MANAGEMENT_FEE = 0;

	function testIntegrationFlow() public {
		uint256 amnt = getAmnt();
		console.log("DEPOSIT 1");
		deposit(user1, amnt);
		noRebalance();
		skip(1);
		withdrawCheck(user1, .5e18);
		console.log("DEPOSIT 2");
		skip(1);
		deposit(user1, amnt);
		console.log("HARVEST");

		harvest();
		adjustPrice(0.9e18);
		// this updates strategy tvl
		vault.getAndUpdateTvl();
		console.log("REBALANCE");
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		adjustPrice(1.2e18);
		console.log("REBALANCE 2");
		skip(1);
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		console.log("WITHDRAW ALL");
		skip(1);

		withdrawAll(user1);
	}

	function testAggregator() public {
		AggregatorVault aggVault = new AggregatorVault(
			ERC20(address(vault.underlying())),
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);
		aggVault.addStrategy(IVaultStrategy(address(vault)));
		aggVault.harvest(0, 0);
	}
}
