// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { StratUtils, IERC20 } from "./StratUtils.sol";
import { SetupImx } from "./SetupImx.sol";
import { SetupHlp } from "./SetupHlp.sol";
import { SetupImxLend } from "./SetupImxLend.sol";
import { SetupStargate } from "./SetupStargate.sol";
import { SetupSynapse } from "./SetupSynapse.sol";

import "hardhat/console.sol";

// These test run for all strategies
abstract contract IntegrationTest is SectorTest, StratUtils {
	function testIntegrationFlow() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		noRebalance();
		withdrawCheck(user1, .5e18);
		deposit(user1, amnt);
		harvest();
		adjustPrice(0.9e18);
		// this updates strategy tvl
		vault.getAndUpdateTvl();
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		adjustPrice(1.19e18);
		rebalance();
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		withdrawAll(user1);
	}

	function testAccounting() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 startBalance = vault.underlyingBalance(user1);
		adjustPrice(1.2e18);
		deposit(user2, amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(user2),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		adjustPrice(.834e18);
		uint256 balance = vault.underlyingBalance(user1);
		assertApproxEqRel(balance, startBalance, .0003e18, "first balance should not decrease");
	}

	function testFlashSwap() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 startBalance = vault.underlyingBalance(user1);

		// trackCost();
		moveUniPrice(1.5e18);
		deposit(user2, amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(user2),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		moveUniPrice(.666e18);
		uint256 balance = vault.underlyingBalance(user1);
		assertGe(balance, startBalance, "first balance should not decrease"); // within .1%
	}

	function testManagerWithdraw() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 shares = vault.totalSupply();
		vm.prank(guardian);
		vault.withdrawFromStrategy(shares, 0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .001e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
		vm.roll(block.number + 1);
		vm.prank(guardian);
		vault.depositIntoStrategy(floatBalance, 0);
	}

	function testClosePosition() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		vm.prank(guardian);
		vault.closePosition(0, 0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .001e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
	}
}

contract IntegrationImx is SetupImx, IntegrationTest {}

contract IntegrationImxLend is SetupImxLend, IntegrationTest {}

contract IntegrationHlp is SetupHlp, IntegrationTest {}

contract IntegrationStargate is SetupStargate, IntegrationTest {}

contract IntegrationSynapse is SetupSynapse, IntegrationTest {}
