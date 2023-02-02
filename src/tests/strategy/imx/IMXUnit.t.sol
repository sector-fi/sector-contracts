// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMXSetup, IUniswapV2Pair, SCYVault, HarvestSwapParams } from "./IMXSetup.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";
import { UnitTestStrategy } from "../common/UnitTestStrategy.sol";
import { IStrategy } from "interfaces/IStrategy.sol";

import "hardhat/console.sol";

contract IMXUnit is IMXSetup, UnitTestStrategy, UnitTestVault {
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
		strategy.getAndUpdateTvl();

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
		uint256 balance = IERC20(address(vault)).balanceOf(user1);
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

		uint256 tvl = strategy.getAndUpdateTvl();
		assertEq(tvl, 0);

		deposit(user1, amount);

		uint256 exchangeRate2 = vault.sharesToUnderlying(1e18);
		assertApproxEqRel(exchangeRate, exchangeRate2, .0011e18, "exchange rate after deposit");
	}

	function testGetMaxTvlFail() public {
		strategy.getAndUpdateTvl();
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

	/// @dev specific conditions needed to meet the edge case:
	// OP_BLOCK = 65972372
	// 	string TEST_STRATEGY = "USDC-ETH-Tarot-Velo";
	function testRebalanceEdge() public {
		deposit(user1, 10 * dec);

		// logTvl(IStrategy(address(strategy)));
		adjustPrice(100e18);
		adjustPrice(.01e18);
		adjustPrice(100e18);
		adjustPrice(.01e18);

		adjustPrice(1.12e18);
		skip(60 * 60 * 24 * 5);
		strategy.getAndUpdateTvl();
		// logTvl(IStrategy(address(strategy)));

		console.log("position offset", strategy.getPositionOffset());
		vm.startPrank(manager);
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10);
		strategy.rebalance(expectedPrice, maxDelta);
		vm.stopPrank();
		console.log("end position offset", strategy.getPositionOffset());
		assertEq(IERC20(config.short).balanceOf(address(strategy)), 0);
	}

	function testRebalanceEdge2() public {
		deposit(user1, 10 * dec);

		// logTvl(IStrategy(address(strategy)));
		// adjustPrice(100e18);
		// adjustPrice(.01e18);
		// adjustPrice(100e18);
		// adjustPrice(.01e18);

		// skip(60 * 60 * 24 * 1000);
		adjustPrice(.9e18);
		strategy.getAndUpdateTvl();
		// logTvl(IStrategy(address(strategy)));

		console.log("position offset", strategy.getPositionOffset());
		vm.startPrank(manager);
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10);
		strategy.rebalance(expectedPrice, maxDelta);
		vm.stopPrank();
		console.log("end position offset", strategy.getPositionOffset());
		// assertEq(IERC20(config.short).balanceOf(address(strategy)), 0);
	}

	function testNativeFlow() public {
		if (!vault.acceptsNativeToken()) return;
		// SCYVault vault = SCYVault(payable(0x5C6079193fA38868f51eac367E622DAda53cf17D));

		uint256 amnt = 1e18;

		vm.startPrank(user1);
		vm.deal(user1, amnt);
		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit{ value: amnt }(user1, address(0), 0, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		uint256 sharesToWithdraw = IERC20(address(vault)).balanceOf(user1);
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vm.prank(user1);
		vault.redeem(user1, sharesToWithdraw, address(0), (minUnderlyingOut * 9990) / 10000);

		assertApproxEqRel(user1.balance, amnt, .001e18);
	}

	// function testDeployments() public {
	// 	IMXCore dstrat = IMXCore(0x2c7BBA60bF6a8b6b042A3b43C9349345DA7ad078);
	// 	SCYVault dvault = SCYVault(payable(0x2c7BBA60bF6a8b6b042A3b43C9349345DA7ad078));
	// 	logTvl(IStrategy(address(dstrat)));
	// 	adjustPrice(100e18);
	// 	adjustPrice(.01e18);
	// 	adjustPrice(100e18);
	// 	adjustPrice(.01e18);
	// 	adjustPrice(1.12e18);
	// 	skip(60 * 60 * 24 * 5);
	// 	dstrat.getAndUpdateTVL();
	// 	logTvl(IStrategy(address(dstrat)));
	// 	console.log("position offset", dstrat.getPositionOffset());
	// 	vm.startPrank(0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A);
	// 	(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10);
	// 	dstrat.rebalance(expectedPrice, maxDelta);
	// 	vm.stopPrank();
	// }

	// function testDebugLiquidation() public {
	// 	IMXCore dstrat = IMXCore(0xdB613730C823F260a1A8aC2DcdD6B8B82b491919);
	// 	SCYVault dvault = SCYVault(payable(0xC6c72289eA5c0e28A5D3377C9d69B27161fA06aE));
	// 	logTvl(IStrategy(address(dstrat)));
	// 	strategy.updateOracle();
	// 	console.log("short balance", IERC20(config.short).balanceOf(address(dstrat)));
	// 	console.log("positionOffset", dstrat.getPositionOffset());
	// 	console.log("loanHealth", dstrat.loanHealth());
	// 	vm.stopPrank();
	// }

	// function testDebugWithdraw() public {
	// 	SCYVault dvault = SCYVault(payable(0xC6c72289eA5c0e28A5D3377C9d69B27161fA06aE));
	// 	address dep = 0xf09c27934A92c56c7C0dD6cBAc858C35fBd5170f;
	// 	uint256 shares = dvault.balanceOf(dep);
	// 	vm.prank(dep);
	// 	dvault.redeem(dep, shares, address(dvault.underlying()), 0);
	// }
}
