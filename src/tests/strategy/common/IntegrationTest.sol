// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../../utils/SectorTest.sol";
import { SCYStratUtils, IERC20 } from "./SCYStratUtils.sol";
import { UniswapMixin } from "./UniswapMixin.sol";

import "hardhat/console.sol";

// These test run for all strategies
abstract contract IntegrationTest is SectorTest, SCYStratUtils {
	function testIntegrationFlow() public {
		uint256 amnt = getAmnt();
		console.log("DEPOSIT 1");
		deposit(user1, amnt);
		noRebalance();
		withdrawCheck(user1, .5e18);
		console.log("DEPOSIT 2");
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
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		console.log("WITHDRAW ALL");
		withdrawAll(user1);
	}
}
