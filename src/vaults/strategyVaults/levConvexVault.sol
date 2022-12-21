// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../ERC5115/SCYStrategy.sol";
import { levConvex } from "../../strategies/gearbox/levConvex.sol";
import { SCYWEpochVault, IERC20, SafeERC20 } from "../ERC5115/SCYWEpochVault.sol";
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
			address(underlying) != address(levConvex(strategy).underlying()) ||
			yieldToken != address(levConvex(strategy).convexRewardPool())
		) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		underlying.safeTransfer(strategy, amount);
		return levConvex(strategy).deposit(amount);
	}

	function _stratRedeem(address recipient, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		// strategy doesn't transfer tokens to user
		// TODO it should?
		amountOut = levConvex(strategy).redeem(yeildTokenAmnt, recipient);
		amntToTransfer = 0;
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return levConvex(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return levConvex(strategy).getTotalTVL();
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		return levConvex(strategy).closePosition();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return levConvex(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return levConvex(strategy).collateralToUnderlying();
	}

	function _stratHarvest(HarvestSwapParams[] calldata params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvested, uint256[] memory)
	{
		harvested = levConvex(strategy).harvest(params);
		return (harvested, new uint256[](0));
	}

	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == yieldToken) return levConvex(strategy).collateralBalance();
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
