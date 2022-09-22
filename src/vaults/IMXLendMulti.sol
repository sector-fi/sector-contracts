// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategyMulti, StrategyMulti as Strategy } from "./scyMulti/SCYStrategyMulti.sol";
import { IPoolToken, IBorrowable } from "../interfaces/imx/IImpermax.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVaultMulti } from "./scyMulti/SCYVaultMulti.sol";
import { SafeETH } from "./../libraries/SafeETH.sol";

// import "hardhat/console.sol";

contract IMXLendMulti is SCYStrategyMulti, SCYVaultMulti {
	using SafeERC20 for IERC20;

	constructor() {}

	function _stratDeposit(Strategy storage strategy, uint256) internal override returns (uint256) {
		return IPoolToken(strategy.addr).mint(address(this));
	}

	function _stratRedeem(
		Strategy storage strategy,
		address to,
		uint256 amount
	) internal override returns (uint256 amountOut, uint256 amntToTransfer) {
		IERC20(strategy.yieldToken).safeTransfer(strategy.addr, amount);
		amntToTransfer = 0;
		amountOut = IPoolToken(strategy.addr).redeem(to);
	}

	function _stratGetAndUpdateTvl(Strategy storage strategy) internal override returns (uint256) {
		// exchange rate does the accrual
		uint256 exchangeRate = IBorrowable(strategy.addr).exchangeRate();
		uint256 balance = IERC20(strategy.addr).balanceOf(address(this));
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function _strategyTvl(Strategy storage strategy) internal view override returns (uint256) {
		uint256 balance = IERC20(strategy.addr).balanceOf(address(this));
		uint256 exchangeRate = IBorrowable(strategy.addr).exchangeRateLast();
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function _stratClosePosition(Strategy storage strategy) internal override returns (uint256) {
		uint256 yeildTokenAmnt = IERC20(strategy.addr).balanceOf(address(this));
		IERC20(strategy.addr).safeTransfer(strategy.addr, yeildTokenAmnt);
		return IPoolToken(strategy.addr).redeem(address(this));
	}

	function _stratMaxTvl(Strategy storage) internal pure override returns (uint256) {
		return type(uint256).max;
	}

	function _stratCollateralToUnderlying(Strategy storage strategy)
		internal
		view
		override
		returns (uint256)
	{
		return IBorrowable(strategy.addr).exchangeRateLast();
	}

	// send funds to user
	function _transferOut(
		uint96,
		address token,
		address to,
		uint256 amount
	) internal virtual override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransfer(to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(uint96, address token) internal view override returns (uint256) {
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
