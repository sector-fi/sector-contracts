// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../scy/SCYStrategy.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "../scy/SCYVault.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IStargateRouter, lzTxObj } from "../../interfaces/stargate/IStargateRouter.sol";
import { IStargatePool } from "../../interfaces/stargate/IStargatePool.sol";
import { IStarchef } from "../../interfaces/stargate/IStarchef.sol";
import { StarChefFarm, FarmConfig } from "../../strategies/adapters/StarChefFarm.sol";

// import "hardhat/console.sol";

// This strategy assumes that sharedDecimans and localDecimals are the same
contract Stargate is SCYStrategy, SCYVault, StarChefFarm {
	using SafeERC20 for IERC20;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy,
		FarmConfig memory _farmConfig
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) StarChefFarm(_farmConfig) {
		underlying.approve(strategy, type(uint256).max);
		IERC20(yieldToken).approve(address(farm), type(uint256).max);
		sendERC20ToStrategy = false;
	}

	function _stratValidate() internal view override {
		if (
			address(underlying) != IStargatePool(yieldToken).token() ||
			IStargatePool(yieldToken).convertRate() != 1
		) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		uint256 lp = (amount * 1e18) / IStargatePool(yieldToken).amountLPtoLD(1e18);
		IStargateRouter(strategy).addLiquidity(strategyId, amount, address(this));
		farm.deposit(farmId, lp);
		return lp;
	}

	function _stratRedeem(address to, uint256 amount)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		farm.withdraw(farmId, amount);
		amntToTransfer = 0;
		amountOut = IStargateRouter(strategy).instantRedeemLocal(strategyId, amount, to);
	}

	function _stratGetAndUpdateTvl() internal view override returns (uint256) {
		return _strategyTvl();
	}

	function _strategyTvl() internal view override returns (uint256) {
		(uint256 balance, ) = farm.userInfo(uint256(farmId), address(this));
		return IStargatePool(yieldToken).amountLPtoLD(balance);
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		(uint256 balance, ) = farm.userInfo(farmId, address(this));
		farm.withdraw(farmId, balance);
		return IStargateRouter(strategy).instantRedeemLocal(strategyId, balance, address(this));
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return IERC20(yieldToken).totalSupply() / 10; // 10% of total deposits
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return IStargatePool(yieldToken).amountLPtoLD(1e18);
	}

	function _selfBalance(address token) internal view override returns (uint256) {
		if (token == address(yieldToken)) {
			(uint256 balance, ) = farm.userInfo(farmId, address(this));
			return balance;
		}
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}

	function _stratHarvest(HarvestSwapParams[] calldata farm1Params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvested, uint256[] memory)
	{
		(uint256 tokenHarvest, uint256 amountOut) = _harvest(farm1Params[0]);
		if (amountOut > 0) _stratDeposit(amountOut);
		harvested = new uint256[](1);
		harvested[0] = tokenHarvest;
	}

	// EMERGENCY GUARDIAN METHODS
	function redeemRemote(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress,
		uint256 _amountLP,
		uint256 _minAmountLD,
		bytes calldata _to,
		lzTxObj memory _lzTxParams
	) external payable onlyRole(GUARDIAN) {
		IStargateRouter(strategy).redeemRemote(
			_dstChainId,
			_srcPoolId,
			_dstPoolId,
			_refundAddress,
			_amountLP,
			_minAmountLD,
			_to,
			_lzTxParams
		);
	}

	function redeemLocal(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress,
		uint256 _amountLP,
		bytes calldata _to,
		lzTxObj memory _lzTxParams
	) external payable onlyRole(GUARDIAN) {
		IStargateRouter(strategy).redeemLocal(
			_dstChainId,
			_srcPoolId,
			_dstPoolId,
			_refundAddress,
			_amountLP,
			_to,
			_lzTxParams
		);
	}

	function sendCredits(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress
	) external payable onlyRole(GUARDIAN) {
		IStargateRouter(strategy).sendCredits(_dstChainId, _srcPoolId, _dstPoolId, _refundAddress);
	}
}