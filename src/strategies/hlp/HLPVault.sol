// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../../vaults/ERC5115/SCYStrategy.sol";
import { HLPCore } from "./HLPCore.sol";
import { SCYVault, IERC20 } from "../../vaults/ERC5115/SCYVault.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

contract HLPVault is SCYStrategy, SCYVault {
	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

	function sendERC20ToStrategy() public pure override returns (bool) {
		return true;
	}

	function _stratValidate() internal view override {
		if (address(underlying) != address(HLPCore(strategy).underlying()))
			revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		return HLPCore(strategy).deposit(amount);
	}

	function _stratRedeem(address recipient, uint256 yeildTokenAmnt)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		// strategy doesn't transfer tokens to user
		// TODO it should?
		amountOut = HLPCore(strategy).redeem(yeildTokenAmnt, recipient);
		return (amountOut, amntToTransfer);
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return HLPCore(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return HLPCore(strategy).getTotalTVL();
	}

	function _stratClosePosition(uint256 slippageParam) internal override returns (uint256) {
		return HLPCore(strategy).closePosition(slippageParam);
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return HLPCore(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return HLPCore(strategy).collateralToUnderlying();
	}

	function _stratHarvest(
		HarvestSwapParams[] calldata farm1Params,
		HarvestSwapParams[] calldata farm2Parms
	) internal override returns (uint256[] memory harvest1, uint256[] memory harvest2) {
		return HLPCore(strategy).harvest(farm1Params, farm2Parms);
	}

	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == yieldToken) return HLPCore(strategy).getLiquidity();
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
