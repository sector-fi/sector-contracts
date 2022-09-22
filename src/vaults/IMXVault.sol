// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "./scy/SCYStrategy.sol";
import { IMX } from "../strategies/imx/IMX.sol";
import { SCYVault } from "./scy/SCYVault.sol";

contract IMXVault is SCYStrategy, SCYVault {
	constructor(
		address _bank,
		address _owner,
		address guardian,
		address manager,
		address _treasury,
		Strategy memory _strategy
	) SCYVault(_bank, _owner, guardian, manager, _treasury, _strategy) {}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		return IMX(strategy).deposit(amount);
	}

	function _stratRedeem(address, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		// strategy doesn't transfer tokens to user
		// TODO it should?
		amountOut = IMX(strategy).redeem(yeildTokenAmnt);
		amntToTransfer = amountOut;
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return IMX(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return IMX(strategy).getTotalTVL();
	}

	function _stratClosePosition() internal override returns (uint256) {
		return IMX(strategy).closePosition();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return IMX(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return IMX(strategy).collateralToUnderlying();
	}
}
