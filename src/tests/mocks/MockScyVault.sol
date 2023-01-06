// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SCYVault } from "../../vaults/ERC5115/SCYVault.sol";
import { SCYStrategy, Strategy } from "../../vaults/ERC5115/SCYStrategy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "./../../libraries/SafeETH.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { Fees, FeeConfig } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";

contract MockScyVault is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	uint256 underlyingBalance;

	constructor(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) Auth(authConfig) Fees(feeConfig) SCYVault(_strategy) {}

	function sendERC20ToStrategy() public pure override returns (bool) {
		return true;
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		uint256 stratBalance = underlying.balanceOf(strategy);
		if (underlyingBalance + amount < stratBalance) revert MissingFunds();
		uint256 supply = MockERC20(strategy).totalSupply();
		uint256 amntToMint = supply == 0 ? amount : (amount * supply) / (stratBalance - amount);
		MockERC20(yieldToken).mint(address(this), amntToMint);
		underlyingBalance = underlying.balanceOf(strategy);
		return amntToMint;
	}

	function _stratRedeem(address to, uint256 shares)
		internal
		override
		returns (uint256 amntOut, uint256 amntToTransfer)
	{
		uint256 stratBalance = underlying.balanceOf(strategy);
		uint256 supply = MockERC20(strategy).totalSupply();
		MockERC20(yieldToken).burn(address(this), shares);

		uint256 amntUnderlying = (shares * stratBalance) / supply;

		MockERC20(address(underlying)).burn(strategy, amntUnderlying);
		MockERC20(address(underlying)).mint(to, amntUnderlying);
		underlyingBalance = underlying.balanceOf(strategy);
		amntToTransfer = to == address(this) ? amntUnderlying : 0;
		return (amntUnderlying, amntToTransfer);
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
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

	function _stratHarvest(HarvestSwapParams[] calldata params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory, uint256[] memory)
	{
		/// simulate harvest profits
		if (params.length > 0) MockERC20(address(underlying)).mint(strategy, params[0].min);
		return (new uint256[](0), new uint256[](0));
	}

	function getFloatingAmount(address token) public view override returns (uint256) {
		if (token == address(underlying)) return underlying.balanceOf(strategy) - underlyingBalance;
		return _selfBalance(token);
	}

	function isValidBaseToken(address token) public view override returns (bool) {
		return token == address(underlying) || token == NATIVE;
	}

	error MissingFunds();
}
