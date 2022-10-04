// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SCYVault } from "../../vaults/scy/SCYVault.sol";
import { SCYStrategy, Strategy } from "../../vaults/scy/SCYStrategy.sol";
import { MockERC20 } from "./MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "./../../libraries/SafeETH.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

contract MockScyVault is SCYStrategy, SCYVault {
	using SafeERC20 for IERC20;

	uint256 underlyingBalance;

	constructor(
		address _owner,
		address guardian,
		address manager,
		Strategy memory _strategy
	) SCYVault(_owner, guardian, manager, _strategy) {}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		if (underlyingBalance + amount < underlying.balanceOf(strategy)) revert MissingFunds();
		MockERC20(strategy).mint(address(this), amount);
		underlyingBalance = underlying.balanceOf(strategy);
		return amount;
	}

	function _stratRedeem(address to, uint256 amount)
		internal
		override
		returns (uint256 amntOut, uint256 amntToTransfer)
	{
		MockERC20(strategy).burn(address(this), amount);
		MockERC20(address(underlying)).burn(strategy, amount);
		MockERC20(address(underlying)).mint(to, amount);

		underlyingBalance = underlying.balanceOf(strategy);
		return (amount, 0);
	}

	function _stratClosePosition() internal override returns (uint256) {
		uint256 tvl = MockERC20(strategy).totalSupply();
		MockERC20(strategy).burn(address(this), totalSupply());
		MockERC20(address(underlying)).burn(strategy, tvl);
		MockERC20(address(underlying)).mint(address(this), tvl);
		underlyingBalance = underlying.balanceOf(strategy);
		return tvl;
	}

	function _stratGetAndUpdateTvl() internal view override returns (uint256) {
		return MockERC20(strategy).totalSupply();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return MockERC20(strategy).totalSupply();
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

	error MissingFunds();
}
