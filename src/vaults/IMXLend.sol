// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "./scy/SCYStrategy.sol";
import { IPoolToken, IBorrowable } from "../interfaces/imx/IImpermax.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "./scy/SCYVault.sol";
import { SafeETH } from "./../libraries/SafeETH.sol";

// import "hardhat/console.sol";

contract IMXLend is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	constructor(
		address _bank,
		address _owner,
		address guardian,
		address manager,
		address _treasury,
		Strategy memory _strategy
	) SCYVault(_bank, _owner, guardian, manager, _treasury, _strategy) {}

	function _stratDeposit(uint256) internal override returns (uint256) {
		return IPoolToken(strategy).mint(address(this));
	}

	function _stratRedeem(address to, uint256 amount)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		IERC20(yieldToken).safeTransfer(strategy, amount);
		amntToTransfer = 0;
		amountOut = IPoolToken(strategy).redeem(to);
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		// exchange rate does the accrual
		uint256 exchangeRate = IBorrowable(strategy).exchangeRate();
		uint256 balance = IERC20(strategy).balanceOf(address(this));
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function _strategyTvl() internal view override returns (uint256) {
		uint256 balance = IERC20(strategy).balanceOf(address(this));
		uint256 exchangeRate = IBorrowable(strategy).exchangeRateLast();
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function _stratClosePosition() internal override returns (uint256) {
		uint256 yeildTokenAmnt = IERC20(strategy).balanceOf(address(this));
		IERC20(strategy).safeTransfer(strategy, yeildTokenAmnt);
		return IPoolToken(strategy).redeem(address(this));
	}

	// TOOD fraction of total deposits
	function _stratMaxTvl() internal pure override returns (uint256) {
		return type(uint256).max;
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return IBorrowable(strategy).exchangeRateLast();
	}

	// send funds to user
	function _transferOut(
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
	function _selfBalance(address token) internal view override returns (uint256) {
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
