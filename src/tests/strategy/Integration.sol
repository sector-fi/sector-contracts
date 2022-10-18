// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { StratUtils, IERC20 } from "./StratUtils.sol";

import "hardhat/console.sol";

// These test run for all strategies
abstract contract IntegrationTest is SectorTest, StratUtils {
	function testIntegrationFlow() public {
		deposit(100e6);
		noRebalance();
		withdrawCheck(.5e18);
		deposit(100e6);
		harvest();
		adjustPrice(0.9e18);
		genericStrategy.getAndUpdateTVL();
		rebalance();
		adjustPrice(1.2e18);
		rebalance();
		withdrawAll();
	}

	function testAccounting() public {
		uint256 amnt = 100e6;
		vm.startPrank(address(2));
		deposit(amnt, address(2));
		vm.stopPrank();
		adjustPrice(1.2e18);
		deposit(amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(address(this)),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		adjustPrice(.833e18);
		uint256 balance = vault.underlyingBalance(address(2));
		assertGt(balance, amnt, "first balance should not decrease"); // within .1%
	}

	function testFlashSwap() public {
		uint256 amnt = 100e6;
		vm.startPrank(address(2));
		deposit(amnt, address(2));
		vm.stopPrank();
		// trackCost();
		moveUniPrice(1.5e18);
		deposit(amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(address(this)),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		moveUniPrice(.666e18);
		uint256 balance = vault.underlyingBalance(address(2));
		assertGt(balance, amnt, "first balance should not decrease"); // within .1%
	}

	function testManagerWithdraw() public {
		uint256 amnt = 1000e6;
		deposit(1000e6);
		// uint256 shares = vault.totalSupply();
		// vault.withdrawFromStrategy(shares, 0);
		vault.closePosition(0, 0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .001e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
		vm.roll(block.number + 1);
		vault.depositIntoStrategy(floatBalance, 0);
	}

	function withdrawCheck(uint256 fraction) public {
		uint256 startTvl = genericStrategy.getTotalTVL();
		withdraw(fraction);

		uint256 tvl = genericStrategy.getTotalTVL();
		assertApproxEqAbs(tvl, (startTvl * (1e18 - fraction)) / 1e18, 10);
		assertApproxEqAbs(vault.underlyingBalance(address(this)), tvl, 10);
	}

	function withdrawAll() public {
		uint256 balance = vault.balanceOf(address(this));

		vault.redeem(address(this), balance, address(underlying), 0);

		uint256 tvl = genericStrategy.getTotalTVL();
		assertEq(tvl, 0, "vault tvl");
		assertEq(vault.balanceOf(address(this)), 0, "account shares");
		assertEq(vault.underlyingBalance(address(this)), 0, "account value");
	}
}
