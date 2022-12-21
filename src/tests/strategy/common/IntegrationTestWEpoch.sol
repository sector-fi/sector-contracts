// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYStratUtils, IERC20 } from "./SCYStratUtils.sol";
import "hardhat/console.sol";

// These test run for all strategies
abstract contract IntegrationTestWEpoch is SCYStratUtils {
	function testIntegrationFlow() public {
		uint256 amnt = getAmnt();
		console.log("DEPOSIT 1");
		deposit(user1, amnt);
		noRebalance();
		console.log("WITHDRAW");
		withdrawEpoch(user1, .5e18);
		console.log("DEPOSIT 2");
		deposit(user1, amnt);
		console.log("HARVEST");
		harvest();
		console.log("ADJUST PRICE");
		adjustPrice(0.9e18);
		// this updates strategy tvl
		vault.getAndUpdateTvl();
		console.log("REBALANCE");
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		adjustPrice(1.2e18);
		console.log("REBALANCE 2");
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		console.log("WITHDRAW ALL");
		withdrawEpoch(user1, 1e18);
		console.log(
			"final loss",
			10000 - (10000 * underlying.balanceOf(user1) * 1e18) / (amnt * (1.5e18))
		);
	}
}
