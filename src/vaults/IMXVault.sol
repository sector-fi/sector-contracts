// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "./scy/SCYStrategy.sol";
import { IMX } from "../strategies/imx/IMX.sol";
import { SCYVault } from "./scy/SCYVault.sol";

contract IMXVault is SCYStrategy, SCYVault {
	// constructor() {};

	function _stratDeposit(Strategy storage strategy, uint256 amount)
		internal
		override
		returns (uint256)
	{
		return IMX(strategy.addr).deposit(amount);
	}

	function _stratRedeem(
		Strategy storage strategy,
		address,
		uint256 yeildTokenAmnt
	) internal override returns (uint256 amountOut, uint256 amntToTransfer) {
		// strategy doesn't transfer tokens to user
		// TODO it should?
		amountOut = IMX(strategy.addr).redeem(yeildTokenAmnt);
		amntToTransfer = amountOut;
	}

	function _stratGetAndUpdateTvl(Strategy storage strategy) internal override returns (uint256) {
		return IMX(strategy.addr).getAndUpdateTVL();
	}

	function _strategyTvl(Strategy storage strategy) internal view override returns (uint256) {
		return IMX(strategy.addr).getTotalTVL();
	}

	function _stratClosePosition(Strategy storage strategy) internal override returns (uint256) {
		return IMX(strategy.addr).closePosition();
	}

	function _stratMaxTvl(Strategy storage strategy) internal view override returns (uint256) {
		return IMX(strategy.addr).getMaxTvl();
	}

	function _stratCollateralToUnderlying(Strategy storage strategy)
		internal
		view
		override
		returns (uint256)
	{
		return IMX(strategy.addr).collateralToUnderlying();
	}
}
