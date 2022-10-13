// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SCYVault } from "../../vaults/scy/SCYVault.sol";
import { SCYStrategy, Strategy } from "../../vaults/scy/SCYStrategy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "./../../libraries/SafeETH.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { Fees, FeeConfig } from "../../common/Fees.sol";

import "hardhat/console.sol";

contract MockScyVault is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	uint256 underlyingBalance;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		if (underlyingBalance + amount < underlying.balanceOf(strategy)) revert MissingFunds();
		MockERC20(yieldToken).mint(address(this), amount);
		underlyingBalance = underlying.balanceOf(strategy);
		return amount;
	}

	function _stratRedeem(address to, uint256 amount)
		internal
		override
		returns (uint256 amntOut, uint256 amntToTransfer)
	{
		MockERC20(yieldToken).burn(address(this), amount);
		MockERC20(address(underlying)).burn(strategy, amount);
		MockERC20(address(underlying)).mint(to, amount);
		underlyingBalance -= amount;
		amntToTransfer = to == address(this) ? amount : 0;
		return (amount, amntToTransfer);
	}

	function _stratClosePosition() internal override returns (uint256) {
		uint256 amount = underlying.balanceOf(strategy);
		MockERC20(yieldToken).burn(strategy, amount);
		MockERC20(address(underlying)).burn(strategy, amount);
		MockERC20(address(underlying)).mint(address(this), amount);
		underlyingBalance = 0;
		return amount;
	}

	function _stratGetAndUpdateTvl() internal view override returns (uint256) {
		return _strategyTvl();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return underlying.balanceOf(address(strategy));
	}

	function _stratMaxTvl() internal pure override returns (uint256) {
		return type(uint256).max;
	}

	function _stratCollateralToUnderlying() internal pure override returns (uint256) {
		return 1e18;
	}

	function _stratValidate() internal override {}

	function _getFloatingAmount(address token) internal view override returns (uint256) {
		if (token == address(underlying)) return underlying.balanceOf(strategy) - underlyingBalance;
		return _selfBalance(token);
	}

	function getBaseTokens() external view override returns (address[] memory res) {
		res[0] = address(underlying);
		res[1] = NATIVE;
	}

	function isValidBaseToken(address token) public view override returns (bool) {
		return token == address(underlying) || token == NATIVE;
	}

	error MissingFunds();
}
