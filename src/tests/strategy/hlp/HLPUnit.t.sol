// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IUniswapV2Pair } from "interfaces/uniswap/IUniswapV2Pair.sol";
import { HarvestSwapParams } from "strategies/mixins/IFarmable.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { HLPSetup, SCYVault } from "./HLPSetup.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";
import { UnitTestStrategy } from "../common/UnitTestStrategy.sol";
import { SectorErrors } from "interfaces/SectorErrors.sol";

import "hardhat/console.sol";

contract HLPUnit is HLPSetup, UnitTestStrategy, UnitTestVault {
	/// INIT

	function testShouldInit() public override {
		assertEq(strategy.vault(), address(vault));
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
		assertEq(strategy.decimals(), underlying.decimals());
	}

	/// ROLES?

	/// EMERGENCY WITHDRAW

	// function testEmergencyWithdraw() public {
	// 	uint256 amount = 1e18;
	// 	underlying.mint(address(strategy), amount);
	// 	SafeETH.safeTransferETH(address(strategy), amount);

	// 	address withdrawTo = address(222);

	// 	tokens.push(underlying);
	// 	strategy.emergencyWithdraw(withdrawTo, tokens);

	// 	assertEq(underlying.balanceOf(withdrawTo), amount);
	// 	assertEq(withdrawTo.balance, amount);

	// 	assertEq(underlying.balanceOf(address(strategy)), 0);
	// 	assertEq(address(strategy).balance, 0);
	// }

	// CONFIG

	function testDepositOverMaxTvl() public {
		uint256 amount = strat.getMaxDeposit() + 1;
		depositRevert(self, amount, SectorErrors.MaxTvlReached.selector);
	}

	function testSafeCollateralRatio() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setSafeCollateralRatio(900);

		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setSafeCollateralRatio(9000);

		strategy.setSafeCollateralRatio(7700);
		assertEq(strategy.safeCollateralRatio(), 7700);

		vm.prank(guardian);
		vm.expectRevert("ONLY_OWNER");
		strategy.setSafeCollateralRatio(7700);

		vm.prank(manager);
		vm.expectRevert("ONLY_OWNER");
		strategy.setSafeCollateralRatio(7700);
	}

	function testMinLoanHealth() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMinLoanHeath(0.9e18);

		strategy.setMinLoanHeath(1.29e18);
		assertEq(strategy.minLoanHealth(), 1.29e18);

		vm.prank(guardian);
		vm.expectRevert("ONLY_OWNER");
		strategy.setMinLoanHeath(1.29e18);

		vm.prank(manager);
		vm.expectRevert("ONLY_OWNER");
		strategy.setMinLoanHeath(1.29e18);
	}

	function testSetMaxPriceMismatch() public {
		strategy.setMaxDefaultPriceMismatch(1e18);
	}

	function testMaxDefaultPriceMismatch() public {
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMaxDefaultPriceMismatch(24);

		uint256 bigMismatch = 2 + strategy.maxAllowedMismatch();
		vm.prank(guardian);
		vm.expectRevert("STRAT: BAD_INPUT");
		strategy.setMaxDefaultPriceMismatch(bigMismatch);

		vm.prank(guardian);
		strategy.setMaxDefaultPriceMismatch(120);
		assertEq(strategy.maxDefaultPriceMismatch(), 120);

		vm.prank(manager);
		vm.expectRevert(_accessErrorString(GUARDIAN, manager));
		strategy.setMaxDefaultPriceMismatch(120);
	}

	/*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

	function testRebalanceLendFuzz(uint256 fuzz) public {
		uint256 priceAdjust = bound(fuzz, 1.1e18, 2e18);

		deposit(self, dec);
		uint256 rebThresh = strategy.rebalanceThreshold();

		adjustPrice(priceAdjust);

		uint256 minLoanHealth = strategy.minLoanHealth();
		if (strategy.loanHealth() <= minLoanHealth) {
			assertGt(strategy.getPositionOffset(), rebThresh);
			strategy.rebalanceLoan();
			assertGt(strategy.loanHealth(), minLoanHealth);
		}
		// skip if we don't need to rebalance
		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance(priceSlippageParam());
		assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);

		// put price back
		adjustPrice(1e36 / priceAdjust);

		if (strategy.getPositionOffset() <= rebThresh) return;
		strategy.rebalance(priceSlippageParam());
		// strategy.logTvl();

		assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);
	}

	// TODO ?
	// function testRebalanceAfterLiquidation() public {
	// 	deposit(self, dec);

	// 	// liquidates borrows and 1/2 of collateral
	// 	strategy.liquidate();

	// 	strategy.rebalance(priceSlippageParam());
	// 	assertApproxEqAbs(strategy.getPositionOffset(), 0, 11);
	// }

	function testPriceOffsetEdge() public {
		deposit(self, dec);

		adjustPrice(1.08e18);

		uint256 health = strategy.loanHealth();
		uint256 positionOffset = strategy.getPositionOffset();

		adjustOraclePrice(1.10e18);

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();

		assertLt(health, strategy.minLoanHealth());

		strategy.rebalanceLoan();
		assertLt(positionOffset, strategy.rebalanceThreshold());

		strategy.rebalance(priceSlippageParam());

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();
		// assertGt(health, strategy.minLoanHealth());
		assertLt(positionOffset, 10);
	}

	function testPriceOffsetEdge2() public {
		deposit(self, dec);

		adjustPrice(0.92e18);

		uint256 health = strategy.loanHealth();
		uint256 positionOffset = strategy.getPositionOffset();

		adjustOraclePrice(0.9e18);

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();

		assertGt(positionOffset, strategy.rebalanceThreshold());
		strategy.rebalance(priceSlippageParam());

		health = strategy.loanHealth();
		positionOffset = strategy.getPositionOffset();
		assertGt(health, strategy.minLoanHealth());
		assertLt(positionOffset, 10);
	}

	function testMaxPriceOffset() public {
		deposit(self, dec);

		moveUniswapPrice(uniPair, address(underlying), short, 0.7e18);

		uint256 offset = priceSlippageParam();
		vm.prank(manager);
		vm.expectRevert("HLP: MAX_MISMATCH");
		strategy.rebalance(offset);

		vm.prank(manager);
		vm.expectRevert("HLP: MAX_MISMATCH");
		strategy.rebalanceLoan();

		vm.prank(guardian);
		vault.closePosition(0, offset);
	}

	function testRebalanceSlippage() public {
		deposit(self, dec);

		// this creates a price offset
		moveUniswapPrice(uniPair, address(underlying), short, 0.7e18);

		vm.prank(address(1));
		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalanceLoan();

		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.rebalance(0);

		vm.expectRevert("HLP: PRICE_MISMATCH");
		vault.closePosition(0, 0);

		vm.expectRevert("HLP: PRICE_MISMATCH");
		strategy.removeLiquidity(1000, 0);
	}

	/*///////////////////////////////////////////////////////////////
	                    HEDGEDLP TESTS
	//////////////////////////////////////////////////////////////*/

	function testWithdrawFromFarm() public {
		deposit(dec);
		assertEq(uniPair.balanceOf(address(strategy)), 0);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.withdrawFromFarm();
		vault.setMaxTvl(0);
		strategy.withdrawFromFarm();
		assertGt(uniPair.balanceOf(address(strategy)), 0);
	}

	function testWithdrawLiquidity() public {
		deposit(dec);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.removeLiquidity(0, 0);
		vault.setMaxTvl(0);
		strategy.withdrawFromFarm();
		uint256 lp = uniPair.balanceOf(address(strategy));
		strategy.removeLiquidity(lp, 0);
		assertEq(uniPair.balanceOf(address(strategy)), 0);
	}

	function testRedeemCollateral() public {
		deposit(dec);
		(, uint256 collateralBalance, uint256 shortPosition, , , ) = strategy.getTVL();
		deal(short, address(strategy), shortPosition / 10);
		vm.expectRevert(IStrategy.NotPaused.selector);
		strategy.redeemCollateral(shortPosition / 10, collateralBalance / 10);
		vault.setMaxTvl(0);
		strategy.redeemCollateral(shortPosition / 10, collateralBalance / 10);
		(, uint256 newCollateralBalance, uint256 newShortPosition, , , ) = strategy.getTVL();
		assertApproxEqAbs(newCollateralBalance, collateralBalance - collateralBalance / 10, 1);
		assertApproxEqAbs(newShortPosition, shortPosition - shortPosition / 10, 1);
	}

	// slippage in basis points
	function priceSlippageParam() public view override returns (uint256 priceOffset) {
		return strategy.getPriceOffset();
	}

	function testClosePositionEdge() public {
		address short = address(0x98878B06940aE243284CA214f92Bb71a2b032B8A);
		uint256 amount = 1000e6;

		deal(address(underlying), user2, amount);
		vm.startPrank(user2);
		underlying.approve(address(vault), amount);
		vault.deposit(user2, address(underlying), amount, amount);
		vm.stopPrank();

		harvest();

		deal(short, address(strategy), 14368479712190599);
		vault.closePosition(0, strategy.getPriceOffset());
	}

	// function testDeployedHarvest() public {
	// 	SCYVault dvault = SCYVault(payable(0xb2e0ff67be42A569f6B1f50a5a43E5fD0952E58a));
	// 	// vm.warp(block.timestamp + 1 * 60 * 60 * 24);
	// 	harvest(dvault);
	// }
}
