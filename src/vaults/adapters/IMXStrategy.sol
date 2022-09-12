// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../scy/SCYStrategy.sol";
import { IMX } from "../../strategies/imx/IMX.sol";

contract IMXStrategy is SCYStrategy {
	function _stratDeposit(Strategy storage strategy, uint256 amount)
		internal
		override
		returns (uint256)
	{
		return IMX(strategy.addr).deposit(amount);
	}

	function _stratRedeem(Strategy storage strategy, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256)
	{
		return IMX(strategy.addr).redeem(yeildTokenAmnt);
	}

	function _stratGetAndUpdateTvl(Strategy storage strategy) internal override returns (uint256) {
		return IMX(strategy.addr).getAndUpdateTVL();
	}

	function _stratGetTvl(Strategy storage strategy) internal view override returns (uint256) {
		return IMX(strategy.addr).getTotalTVL();
	}

	function _stratClosePosition(Strategy storage strategy) internal override returns (uint256) {
		return IMX(strategy.addr).closePosition();
	}

	function _stratMaxTvl(Strategy storage strategy) internal view override returns (uint256) {
		return IMX(strategy.addr).getMaxTvl();
	}
}
