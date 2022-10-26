// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../scy/SCYStrategy.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "../scy/SCYVault.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IStargateRouter } from "../../interfaces/strategies/IStargateRouter.sol";
import { IStargatePool } from "../../interfaces/strategies/IStargatePool.sol";

import "hardhat/console.sol";

// This strategy assumes that sharedDecimans and localDecimals are the same
contract Stargate is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	IStargatePool public pool;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy,
		IStargatePool _pool
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {
		underlying.approve(strategy, type(uint256).max);
	}

	function _stratValidate() internal view override {
		if (
			address(underlying) != IStargatePool(yieldToken).token() ||
			IStargatePool(yieldToken).convertRate() != 1
		) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		IStargateRouter(strategy).addLiquidity(strategyId, amount, address(this));
	}

	function _stratRedeem(address to, uint256 amount)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		amntToTransfer = 0;
		amountOut = IStargateRouter(strategy).instantRedeemLocal(strategyId, amount, to);
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		// exchange rate does the accrual
		return IERC20(yieldToken).balanceOf(address(this));
	}

	function _strategyTvl() internal view override returns (uint256) {
		return IERC20(yieldToken).balanceOf(address(this));
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		uint256 yeildTokenAmnt = IERC20(yieldToken).balanceOf(address(this));
		IERC20(strategy).safeTransfer(strategy, yeildTokenAmnt);
		return
			IStargateRouter(yieldToken).instantRedeemLocal(
				strategyId,
				yeildTokenAmnt,
				address(this)
			);
	}

	// TOOD fraction of total deposits
	function _stratMaxTvl() internal view override returns (uint256) {
		return IERC20(yieldToken).totalSupply() / 10; // 10% of total deposits
	}

	function _stratCollateralToUnderlying() internal pure override returns (uint256) {
		return 1;
	}

	function _stratHarvest(
		HarvestSwapParams[] calldata farm1Params,
		HarvestSwapParams[] calldata farm2Parms
	) internal override returns (uint256[] memory harvest1, uint256[] memory harvest2) {}
}
