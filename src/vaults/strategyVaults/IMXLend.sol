// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../ERC5115/SCYStrategy.sol";
import { IPoolToken, IBorrowable } from "../../interfaces/imx/IImpermax.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "../ERC5115/SCYVault.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";

contract IMXLend is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

	function _stratValidate() internal view override {
		if (
			address(underlying) != IPoolToken(strategy).underlying() ||
			yieldToken != address(strategy)
		) revert InvalidStrategy();
	}

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

	function _stratClosePosition(uint256) internal override returns (uint256) {
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

	function _stratHarvest(
		HarvestSwapParams[] calldata farm1Params,
		HarvestSwapParams[] calldata farm2Parms
	) internal override returns (uint256[] memory harvest1, uint256[] memory harvest2) {}

	function getFloatingAmount(address token) public view override returns (uint256) {
		if (token == address(underlying))
			return underlying.balanceOf(strategy) - IPoolToken(strategy).totalBalance();
		return _selfBalance(token);
	}
}
