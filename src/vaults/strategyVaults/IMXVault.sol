// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../scy/SCYStrategy.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { SCYVault, IERC20 } from "..//scy/SCYVault.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

contract IMXVault is SCYStrategy, SCYVault {
	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

	function _stratValidate() internal view override {
		if (
			address(underlying) != address(IMX(strategy).underlying()) ||
			yieldToken != address(IMX(strategy).collateralToken())
		) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		return IMX(strategy).deposit(amount);
	}

	function _stratRedeem(address recipient, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		// strategy doesn't transfer tokens to user
		// TODO it should?
		amountOut = IMX(strategy).redeem(yeildTokenAmnt, recipient);
		amntToTransfer = 0;
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return IMX(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return IMX(strategy).getTotalTVL();
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		return IMX(strategy).closePosition();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return IMX(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return IMX(strategy).collateralToUnderlying();
	}

	function _stratHarvest(HarvestSwapParams[] calldata params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvest1, uint256[] memory)
	{
		harvest1 = IMX(strategy).harvest(params);
	}

	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == yieldToken) return IERC20(token).balanceOf(strategy);
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
