// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../utils/PriceUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { HLPConfig, HarvestSwapParams } from "interfaces/Structs.sol";
import { SCYVault } from "vaults/ERC5115/SCYVault.sol";
import { HLPCore } from "strategies/hlp/HLPCore.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStrategy } from "interfaces/IStrategy.sol";

import "hardhat/console.sol";

abstract contract StratUtils is SectorTest, PriceUtils {
	using UniUtils for IUniswapV2Pair;

	uint256 BASIS = 10000;
	uint256 mLp;

	SCYVault vault;

	HarvestSwapParams harvestParams;
	HarvestSwapParams harvestLendParams;

	IERC20 underlying;
	IUniswapV2Pair uniPair;
	address short;
	IStrategy strat;

	uint256 dec;
	bytes32 GUARDIAN;
	bytes32 MANAGER;

	function configureUtils(
		address _underlying,
		address _short,
		address _uniPair,
		address _strategy
	) public {
		underlying = IERC20(_underlying);
		short = _short;
		uniPair = IUniswapV2Pair(_uniPair);
		strat = IStrategy(_strategy);
		dec = 10**underlying.decimals();
		GUARDIAN = vault.GUARDIAN();
		MANAGER = vault.MANAGER();
	}

	function deposit(uint256 amount) public {
		deposit(address(this), amount);
	}

	function depositRevert(
		address user,
		uint256 amnt,
		bytes memory err
	) public {
		deal(address(underlying), user, amnt);
		vm.startPrank(user);
		underlying.approve(address(vault), amnt);
		vm.expectRevert(err);
		vault.deposit(user, address(underlying), amnt, 0);
		vm.stopPrank();
	}

	function deposit(address user, uint256 amount) public {
		uint256 startTvl = vault.getAndUpdateTvl();
		uint256 startAccBalance = vault.underlyingBalance(user);
		deal(address(underlying), user, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);

		vm.startPrank(user);
		underlying.approve(address(vault), amount);
		vault.deposit(user, address(underlying), amount, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		uint256 tvl = vault.getAndUpdateTvl();
		uint256 endAccBalance = vault.underlyingBalance(user);
		assertApproxEqRel(tvl, startTvl + amount, .01e18, "tvl should update");
		assertApproxEqRel(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			.01e18,
			"underlying balance"
		);
		assertEq(vault.getFloatingAmount(address(underlying)), 0);
	}

	function withdrawAmnt(address user, uint256 amnt) public {
		uint256 balance = vault.underlyingBalance(user);
		if (balance == 0) return;
		if (amnt > balance) amnt = balance;
		withdraw(user, (1e18 * amnt) / balance);
	}

	function withdraw(address user, uint256 fraction) public {
		uint256 sharesToWithdraw = (vault.balanceOf(user) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vm.prank(user);
		vault.redeem(
			user,
			sharesToWithdraw,
			address(underlying),
			(minUnderlyingOut * 9990) / 10000
		);
	}

	function withdrawCheck(address user, uint256 fraction) public {
		uint256 startTvl = vault.getAndUpdateTvl(); // us updates iterest
		withdraw(user, fraction);
		uint256 tvl = vault.getAndUpdateTvl();
		assertApproxEqRel(tvl, (startTvl * (1e18 - fraction)) / 1e18, .00001e18, "tvl");
		assertApproxEqRel(vault.underlyingBalance(user), tvl, .00001e18, "tvl balance");
	}

	function withdrawAll(address user) public {
		uint256 balance = vault.balanceOf(user);
		vm.prank(user);
		vault.redeem(user, balance, address(underlying), 0);

		skip(7 days);
		uint256 fees = vault.underlyingBalance(treasury);

		uint256 tvl = vault.getStrategyTvl();

		assertApproxEqAbs(tvl, fees, vault.sharesToUnderlying(mLp) + 10, "strategy tvl");

		assertEq(vault.balanceOf(user), 0, "account shares");
		assertEq(vault.underlyingBalance(user), 0, "account value");
	}

	function logTvl(IStrategy _strategy) internal view {
		(
			uint256 tvl,
			uint256 collateralBalance,
			uint256 shortPosition,
			uint256 borrowBalance,
			uint256 lpBalance,
			uint256 underlyingBalance
		) = _strategy.getTVL();
		console.log("tvl", tvl);
		console.log("collateralBalance", collateralBalance);
		console.log("shortPosition", shortPosition);
		console.log("borrowBalance", borrowBalance);
		console.log("lpBalance", lpBalance);
		console.log("underlyingBalance", underlyingBalance);
	}

	function moveUniPrice(uint256 fraction) public virtual {
		if (address(uniPair) == address(0)) return;
		moveUniswapPrice(uniPair, address(underlying), short, fraction);
	}

	function rebalance() public virtual;

	function harvest() public virtual;

	function noRebalance() public virtual;

	function adjustPrice(uint256 fraction) public virtual;

	// slippage in basis points only used by hlp strat
	function priceSlippageParam() public view virtual returns (uint256) {
		return 0;
	}

	function getAmnt() public view returns (uint256) {
		// if (vault.acceptsNativeToken()) return 1e18;
		uint256 d = vault.underlyingDecimals();
		if (d == 6) return 1000e6;
		if (d == 18) return 1e18;
	}
}
