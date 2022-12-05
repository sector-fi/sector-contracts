// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SetupImx, IUniswapV2Pair } from "./SetupImx.sol";
import { UnitTestStrategy } from "./UnitTestStrategy.sol";

import "hardhat/console.sol";

contract UnitTestImx is SetupImx, UnitTestStrategy {
	function testLoanHealth() public {
		console.log("max tvl", vault.getMaxTvl());
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice(maxAdjust);
		assertApproxEqAbs(strategy.loanHealth(), 1e18, 5e14);
	}

	function testLoanHealthRebalance() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice((maxAdjust * 3) / 2);
		rebalance();
	}

	function testLoanHealthWithdraw() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice(maxAdjust);
		uint256 balance = vault.balanceOf(user1);
		vm.prank(user1);
		vault.redeem(user1, (balance * .2e18) / 1e18, address(underlying), 0);
	}

	function testExtremeDivergence() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		adjustPrice(1e18); // set oracle equal to current price

		// only move uniswap price, not oracle
		moveUniswapPrice(
			IUniswapV2Pair(config.uniPair),
			address(config.underlying),
			config.short,
			.8e18
		);

		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;

		vm.expectRevert(IMXCore.OverMaxPriceOffset.selector);
		vm.prank(manager);
		strategy.rebalance(expectedPrice, maxDelta);

		vm.prank(guardian);
		strategy.rebalance(expectedPrice, maxDelta);
		assertGt(strategy.loanHealth(), 1.002e18);
	}

	function testLeverageUpdate() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);

		// this gets us to 2x leverage (instead of 5x)
		ICollateral collateral = ICollateral(strategy.collateralToken());

		uint256 lev1 = 2e54 / collateral.liquidationIncentive() / collateral.safetyMarginSqrt();

		strategy.setSafetyMarginSqrt(lev1);

		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10);
		strategy.rebalance(expectedPrice, maxDelta);

		adjustPrice(1.1e18);

		deposit(user2, amnt);

		assertApproxEqRel(vault.underlyingBalance(user1), vault.underlyingBalance(user2), .003e18);
	}

	function testEdgeCases() public {
		uint256 amount = 1.5e18;
		deposit(user1, amount);
		uint256 exchangeRate = vault.sharesToUnderlying(1e18);
		// harvest();
		// vm.warp(block.timestamp + 1 * 60 * 60 * 24);

		withdraw(user1, 1e18);
		console.log(IERC20(vault.yieldToken()).balanceOf(vault.strategy())); // Saves an extra SLOAD if totalSupply is non-zero.

		deal(address(underlying), user1, amount);
		vm.startPrank(user1);
		underlying.approve(address(vault), amount);
		vault.deposit(user1, address(underlying), amount, 0);
		vm.stopPrank();

		uint256 exchangeRate2 = vault.sharesToUnderlying(1e18);
		assertApproxEqRel(exchangeRate, exchangeRate2, .001e18, "exchange rate after deposit");
	}

	function testGetMaxTvlFail() public {
		strategy.getAndUpdateTVL();
		uint256 maxTvl = strategy.getMaxTvl();
		deposit(user1, maxTvl - 1);
		vm.warp(block.timestamp + 30 * 60 * 60 * 24);
		strategy.getMaxTvl();
		// uint256 tvl = strategy.getAndUpdateTVL();
		// deposit(user1, strategy.getMaxTvl() - tvl - 1);
	}
}
