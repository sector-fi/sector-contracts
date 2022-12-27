// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMXSetup, IUniswapV2Pair } from "./IMXSetup.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";
import { UnitTestStrategy } from "../common/UnitTestStrategy.sol";

import "hardhat/console.sol";

contract IMXUnit is IMXSetup, UnitTestVault, UnitTestStrategy {
	function testLoanHealth() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);

		// ICollateral collateral = ICollateral(strategy.collateralToken());
		// IUniswapV2Pair p = IUniswapV2Pair(collateral.underlying());
		// console.log("c u", collateral.underlying(), address(uniPair));
		// (uint256 p1, uint256 p2) = collateral.getPrices();
		// uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / collateral.liquidationIncentive();
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;

		adjustPrice(maxAdjust);
		strategy.getAndUpdateTVL();

		assertApproxEqRel(strategy.loanHealth(), 1e18, .001e18);
	}

	function testLoanHealthRebalance() public {
		deposit(user1, dec);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice((maxAdjust * 3) / 2);
		rebalance();
	}

	function testLoanHealthWithdraw() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice((maxAdjust * 9) / 10);
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

		ICollateral collateral = ICollateral(strategy.collateralToken());

		// this gets us to 2x leverage (instead of 5x)
		uint256 lev1 = 2e54 / collateral.liquidationIncentive() / collateral.safetyMarginSqrt();

		strategy.setSafetyMarginSqrt(lev1);

		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10);
		strategy.rebalance(expectedPrice, maxDelta);

		deposit(user2, amnt);

		assertApproxEqRel(vault.underlyingBalance(user1), vault.underlyingBalance(user2), .003e18);
	}

	function testEdgeCases() public {
		uint256 amount = getAmnt();

		deposit(user1, amount);
		uint256 exchangeRate = vault.sharesToUnderlying(1e18);

		withdraw(user1, 1e18);

		uint256 tvl = strategy.getAndUpdateTVL();
		assertEq(tvl, 0);

		deposit(user1, amount);

		uint256 exchangeRate2 = vault.sharesToUnderlying(1e18);
		assertApproxEqRel(exchangeRate, exchangeRate2, .0011e18, "exchange rate after deposit");
	}

	function testGetMaxTvlFail() public {
		strategy.getAndUpdateTVL();
		uint256 maxTvl = strategy.getMaxTvl();
		deposit(user1, maxTvl - 1);
		vm.warp(block.timestamp + 30 * 60 * 60 * 24);
		strategy.getMaxTvl();
	}

	function testStaleOracle() public {
		vm.warp(block.timestamp + 30 * 60 * 60 * 24);
		strategy.updateOracle();
		// this works also
		// strategy.shortToUnderlyingOracleUpdate(1e18);
		strategy.shortToUnderlyingOracle(1e18);
	}

	function testStaleOracleRebalance() public {
		deposit(user1, dec);
		// advance 60m this will make the orace stale
		vm.warp(block.timestamp + 60 * 60 * 60);
		noRebalance();
	}

	function testDeployments() public {
		IMXCore dstrat = IMXCore(0xB3E829d2aE0944a147549330a65614CD095F34c9);
		console.log(address(dstrat.sBorrowable()), address(dstrat.uBorrowable()));
		console.log("max", dstrat.getMaxTvl());
	}
}
