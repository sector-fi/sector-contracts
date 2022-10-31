// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../ERC5115/SCYStrategy.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "../ERC5115/SCYVault.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IStargateRouter, lzTxObj } from "../../interfaces/stargate/IStargateRouter.sol";
import { ISynapseSwap } from "../../interfaces/synapse/ISynapseSwap.sol";
import { MiniChef2Farm, FarmConfig } from "../../strategies/adapters/MiniChef2Farm.sol";

// import "hardhat/console.sol";

// This strategy assumes that sharedDecimans and localDecimals are the same
contract Synapse is SCYStrategy, MiniChef2Farm, SCYVault {
	using SafeERC20 for IERC20;

	uint256 _nTokens;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy,
		FarmConfig memory _farmConfig
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) MiniChef2Farm(_farmConfig) {
		underlying.safeApprove(strategy, type(uint256).max);
		IERC20(yieldToken).safeApprove(address(farm), type(uint256).max);
		IERC20(yieldToken).safeApprove(strategy, type(uint256).max);
		sendERC20ToStrategy = false;
		_nTokens = ISynapseSwap(strategy).calculateRemoveLiquidity(1).length;
	}

	function _stratValidate() internal view override {
		if (underlying != ISynapseSwap(strategy).getToken(uint8(strategyId)))
			revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		uint256[] memory amounts = new uint256[](_nTokens);
		amounts[strategyId] = amount;
		// min LP tokens is checked in redeem method
		uint256 lp = ISynapseSwap(strategy).addLiquidity(amounts, 0, block.timestamp);
		_depositIntoFarm(lp);
		return lp;
	}

	function _stratRedeem(address, uint256 amount)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		_withdrawFromFarm(amount);
		amountOut = ISynapseSwap(strategy).removeLiquidityOneToken(
			amount,
			uint8(strategyId),
			0,
			block.timestamp
		);
		amntToTransfer = amountOut;
	}

	function _stratGetAndUpdateTvl() internal view override returns (uint256) {
		return _strategyTvl();
	}

	function _strategyTvl() internal view override returns (uint256) {
		(uint256 balance, ) = farm.userInfo(uint256(farmId), address(this));
		return ISynapseSwap(strategy).calculateRemoveLiquidityOneToken(balance, uint8(strategyId));
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		(uint256 balance, ) = farm.userInfo(farmId, address(this));
		_withdrawFromFarm(balance);
		return
			ISynapseSwap(strategy).removeLiquidityOneToken(
				balance,
				uint8(strategyId),
				0,
				block.timestamp
			);
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return IERC20(yieldToken).totalSupply() / 10; // 10% of total deposits
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return ISynapseSwap(strategy).getVirtualPrice();
	}

	function _selfBalance(address token) internal view override returns (uint256) {
		if (token == address(yieldToken)) return _getFarmLp();
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}

	function _stratHarvest(HarvestSwapParams[] calldata farm1Params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvested, uint256[] memory)
	{
		(uint256 tokenHarvest, uint256 amountOut) = _harvestFarm(farm1Params[0]);
		if (amountOut > 0) _stratDeposit(amountOut);
		harvested = new uint256[](1);
		harvested[0] = tokenHarvest;
	}

	// function pendingHarvest() public returns (uint256) {
	// 	farm.pendingSynapse(farmId, address(this));
	// }
}
