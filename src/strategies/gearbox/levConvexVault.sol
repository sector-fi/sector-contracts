// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../../vaults/ERC5115/SCYStrategy.sol";
import { ILevConvex } from "./ILevConvex.sol";
import { SCYWEpochVault, IERC20, SafeERC20 } from "../../vaults/ERC5115/SCYWEpochVault.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";

contract levConvexVault is SCYStrategy, SCYWEpochVault {
	using SafeERC20 for IERC20;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYWEpochVault(_strategy) {}

	function _stratValidate() internal view override {
		if (
			address(underlying) != address(ILevConvex(strategy).underlying()) ||
			yieldToken != address(ILevConvex(strategy).convexRewardPool())
		) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		underlying.safeTransfer(strategy, amount);
		return ILevConvex(strategy).deposit(amount);
	}

	function _stratRedeem(address recipient, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		amountOut = ILevConvex(strategy).redeem(yeildTokenAmnt, recipient);
		amntToTransfer = 0;
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return ILevConvex(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return ILevConvex(strategy).getTotalTVL();
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		return ILevConvex(strategy).closePosition();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return ILevConvex(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return ILevConvex(strategy).collateralToUnderlying();
	}

	function _stratHarvest(HarvestSwapParams[] calldata params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvested, uint256[] memory)
	{
		harvested = ILevConvex(strategy).harvest(params);
		return (harvested, new uint256[](0));
	}

	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == yieldToken) return ILevConvex(strategy).collateralBalance();
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
