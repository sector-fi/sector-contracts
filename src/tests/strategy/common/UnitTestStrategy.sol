// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { SCYStratUtils } from "./SCYStratUtils.sol";

import "hardhat/console.sol";

abstract contract UnitTestStrategy is SCYStratUtils {
	IERC20[] tokens;

	/// INIT

	function testShouldInit() public virtual {
		// assertTrue(strat.isInitialized());
		assertEq(strat.vault(), address(vault));
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		assertEq(strat.decimals(), underlying.decimals());
	}

	/// ROLES?

	/// EMERGENCY WITHDRAW

	// function testEmergencyWithdraw() public {
	// 	uint256 amount = 1e18;
	// 	underlying.mint(address(strategy), amount);
	// 	SafeETH.safeTransferETH(address(strategy), amount);

	// 	address withdrawTo = address(222);

	// 	tokens.push(underlying);
	// 	strat.emergencyWithdraw(withdrawTo, tokens);

	// 	assertEq(underlying.balanceOf(withdrawTo), amount);
	// 	assertEq(withdrawTo.balance, amount);

	// 	assertEq(underlying.balanceOf(address(strategy)), 0);
	// 	assertEq(address(strategy).balance, 0);
	// }

	// CONFIG

	function testRebalanceThreshold() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strat.setRebalanceThreshold(90);

		strat.setRebalanceThreshold(500);
		assertEq(strat.rebalanceThreshold(), 500);

		vm.prank(guardian);
		vm.expectRevert("ONLY_OWNER");
		strat.setRebalanceThreshold(500);

		vm.prank(manager);
		vm.expectRevert("ONLY_OWNER");
		strat.setRebalanceThreshold(500);
	}

	function testSetMaxTvl() public {
		strat.setMaxTvl(dec);

		assertEq(strat.getMaxTvl(), dec);
		deposit(dec);

		strat.setMaxTvl(dec / 2);

		assertEq(strat.getMaxTvl(), dec / 2);

		vm.prank(user1);
		vm.expectRevert(_accessErrorString(GUARDIAN, user1));
		strat.setMaxTvl(2 * dec);
	}

	// TODO use setMaxPriceOffset?
	// function testMaxDefaultPriceMismatch() public {
	// 	vm.expectRevert("STRAT: BAD_INPUT");
	// 	strat.setMaxDefaultPriceMismatch(24);

	// 	uint256 bigMismatch = 2 + strat.maxAllowedMismatch();
	// 	vm.prank(guardian);
	// 	vm.expectRevert("STRAT: BAD_INPUT");
	// 	strat.setMaxDefaultPriceMismatch(bigMismatch);

	// 	vm.prank(guardian);
	// 	strat.setMaxDefaultPriceMismatch(120);
	// 	assertEq(strat.maxDefaultPriceMismatch(), 120);

	// 	vm.prank(manager);
	// 	vm.expectRevert(_accessErrorString(GUARDIAN, manager));
	// 	strat.setMaxDefaultPriceMismatch(120);
	// }

	/*///////////////////////////////////////////////////////////////
	                    DEPOSIT/WITHDRAW FAIL TESTS
	//////////////////////////////////////////////////////////////*/

	function testWithdrawRebalanceLoan() public {
		deposit(self, dec);
		adjustPrice(1.2e18);
		uint256 healthBeforeWithdraw = strat.loanHealth();
		withdraw(self, .9e18);
		uint256 health = strat.loanHealth();
		assertApproxEqRel(healthBeforeWithdraw, health, .0001e18);
	}

	function testWithdrawAfterPriceUp() public {
		deposit(self, dec);

		adjustPrice(1.08e18);

		uint256 balance = vault.underlyingBalance(user1);
		uint256 withdrawAmt = (9 * balance) / 10;
		withdrawAmnt(user1, withdrawAmt);

		assertEq(underlying.balanceOf(user1), withdrawAmt);
	}

	function testWithdrawAfterPriceDown() public {
		deposit(user1, dec);

		adjustPrice(.92e18);

		uint256 balance = vault.underlyingBalance(user1);
		uint256 withdrawAmt = (9 * balance) / 10;

		// we have extra undrlying because of movePrice tx
		withdrawAmnt(user1, withdrawAmt);
		assertApproxEqRel(underlying.balanceOf(user1), withdrawAmt, .001e18);
	}

	/*///////////////////////////////////////////////////////////////
	                    REBALANCE TESTS
	//////////////////////////////////////////////////////////////*/
	function testRebalanceSimple() public {
		deposit(self, dec);
		// _rebalanceDown price up -> LP down
		assertEq(strat.getPositionOffset(), 0);

		// 10% price increase should move position offset by more than 4%
		adjustPrice(1.1e18);

		assertGt(strat.getPositionOffset(), 400);

		rebalance();
		assertLe(strat.getPositionOffset(), 10);

		// _rebalanceUp price down -> LP up
		adjustPrice(.909e18);

		assertGt(strat.getPositionOffset(), 400);
		rebalance();
		assertLe(strat.getPositionOffset(), 10);
	}

	function testRebalanceFuzz(uint256 fuzz) public {
		uint256 priceAdjust = bound(fuzz, uint256(.6e18), uint256(2e18));
		uint256 rebThresh = strat.rebalanceThreshold();

		deposit(self, dec);

		adjustPrice(priceAdjust);

		// skip if we don't need to rebalance
		// add some padding so that we can go back easier to account on % change going back
		if (strat.getPositionOffset() <= rebThresh) return;
		rebalance();

		assertApproxEqAbs(strat.getPositionOffset(), 0, 11);

		// put price back
		adjustPrice(1e36 / priceAdjust);

		if (strat.getPositionOffset() <= rebThresh) return;
		rebalance();
		assertApproxEqAbs(strat.getPositionOffset(), 0, 10);
	}

	function testFailRebalance() public {
		deposit(self, dec);
		rebalance();
	}

	// TODO ?
	// function testRebalanceAfterLiquidation() public {
	// 	deposit(self, dec);

	// 	// liquidates borrows and 1/2 of collateral
	// 	strat.liquidate();

	// 	strat.rebalance(strat.getPriceOffset());
	// 	assertApproxEqAbs(strat.getPositionOffset(), 0, 11);
	// }

	// function testPriceOffsetEdge() public {
	// 	deposit(self, dec);

	// 	adjustPrice(1.08e18);

	// 	uint256 health = strat.loanHealth();
	// 	uint256 positionOffset = strat.getPositionOffset();

	// 	adjustOraclePrice(1.10e18);

	// 	health = strat.loanHealth();
	// 	positionOffset = strat.getPositionOffset();

	// 	assertLt(health, strat.minLoanHealth());

	// 	strat.rebalanceLoan();
	// 	assertLt(positionOffset, strat.rebalanceThreshold());

	// 	strat.rebalance(strat.getPriceOffset());

	// 	health = strat.loanHealth();
	// 	positionOffset = strat.getPositionOffset();
	// 	// assertGt(health, strat.minLoanHealth());
	// 	assertLt(positionOffset, 10);
	// }

	// function testPriceOffsetEdge2() public {
	// 	deposit(self, dec);

	// 	adjustPrice(0.92e18);

	// 	uint256 health = strat.loanHealth();
	// 	uint256 positionOffset = strat.getPositionOffset();

	// 	adjustOraclePrice(0.9e18);

	// 	health = strat.loanHealth();
	// 	positionOffset = strat.getPositionOffset();

	// 	assertGt(positionOffset, strat.rebalanceThreshold());
	// 	strat.rebalance(strat.getPriceOffset());

	// 	health = strat.loanHealth();
	// 	positionOffset = strat.getPositionOffset();
	// 	assertGt(health, strat.minLoanHealth());
	// 	assertLt(positionOffset, 10);
	// }

	/////////////
	///// Close Position Tests

	function testClosePosition() public {
		uint256 amnt = getAmnt();
		deposit(self, amnt);

		vault.closePosition(0, priceSlippageParam());
		assertApproxEqAbs(underlying.balanceOf(address(strat)), 0, 10);
		assertApproxEqRel(underlying.balanceOf(address(vault)), amnt, .001e18);

		assertZeroPosition();

		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .005e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);

		uint256 priceOffset = priceSlippageParam();
		vm.expectRevert(_accessErrorString(GUARDIAN, user1));
		vm.prank(user1);
		vault.closePosition(0, priceOffset);
	}

	function testClosePositionWithOffsetFuzz(uint256 fuzz) public {
		uint256 priceAdjust = bound(fuzz, .5e18, 2e18);

		deposit(self, dec);

		adjustPrice(priceAdjust);

		uint256 priceOffset = priceSlippageParam();
		vault.closePosition(0, priceOffset);
		assertZeroPosition();
	}

	function testClosePositionFuzz(uint256 fuzz) public {
		uint256 tvl = strat.getTotalTVL();
		uint256 min = getAmnt() / 100;
		fuzz = bound(fuzz, min, strat.getMaxTvl() - tvl);
		deposit(self, fuzz);

		vault.closePosition(0, priceSlippageParam());
		assertZeroPosition();
	}

	/*///////////////////////////////////////////////////////////////
	                    HEDGEDLP TESTS
	//////////////////////////////////////////////////////////////*/

	function testDepositOverMaxTvl() public {
		strat.setMaxTvl(dec);
		depositRevert(self, 2 * dec, "STRAT: OVER_MAX_TVL");
	}

	// included in fuzz below, but used for coverage
	function testClosePositionWithOffset() public {
		deposit(self, dec);

		adjustPrice(0.5e18);

		uint256 priceOffset = priceSlippageParam();
		vault.closePosition(0, priceOffset);
		assertZeroPosition();
	}

	function testRebalanceClosedPosition() public {
		deposit(dec);
		vault.closePosition(0, 0);
		uint256 positionOffset = strat.getPositionOffset();
		assertEq(positionOffset, 0);
	}

	// UTILS

	function assertZeroPosition() public {
		(, uint256 collateralBalance, uint256 borrowPosition, , , ) = strat.getTVL();
		assertApproxEqAbs(borrowPosition, 0, 10);
		assertApproxEqAbs(collateralBalance, 0, 10);
		(uint256 uLp, uint256 sLp) = strat.getLPBalances();
		assertEq(uLp, 0);
		assertEq(sLp, 0);
		assertApproxEqAbs(underlying.balanceOf(address(strat)), 0, 10);
	}
}
