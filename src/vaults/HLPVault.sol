// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "./scy/SCYStrategy.sol";
import { HLPCore } from "../strategies/hlp/HLPCore.sol";
import { SCYVault, IERC20 } from "./scy/SCYVault.sol";
import { AuthConfig, Auth } from "../common/Auth.sol";
import { FeeConfig, Fees } from "../common/Fees.sol";

contract HLPVault is SCYStrategy, SCYVault {
	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

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
		amntToTransfer = 0;
	}

	function _stratGetAndUpdateTvl() internal override returns (uint256) {
		return HLPCore(strategy).getAndUpdateTVL();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return HLPCore(strategy).getTotalTVL();
	}

	function _stratClosePosition() internal pure override returns (uint256) {
		revert NotImplemented();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return HLPCore(strategy).getMaxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return HLPCore(strategy).collateralToUnderlying();
	}

	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == yieldToken) return HLPCore(strategy).getLiquidity();
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}
}
