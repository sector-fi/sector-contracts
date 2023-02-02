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
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { StratAuthLight } from "../../common/StratAuthLight.sol";

// import "hardhat/console.sol";

contract MockScyVault is ISCYStrategy, StratAuthLight {
	using SafeERC20 for IERC20;

	uint256 underlyingBalance;

	IERC20 public underlying;
	address public lpToken;

	constructor(
		address _underlying,
		address _lpToken,
		address _vault
	) {
		underlying = IERC20(_underlying);
		vault = _vault;
		lpToken = _lpToken;
	}

	function deposit(uint256 amount) public onlyVault returns (uint256) {
		underlying.transfer(address(lpToken), amount);

		uint256 supply = MockERC20(lpToken).totalSupply();
		uint256 stratBalance = underlying.balanceOf(address(lpToken));

		uint256 amntToMint = supply == 0 ? amount : (amount * supply) / (stratBalance - amount);

		MockERC20(lpToken).mint(address(this), amntToMint);
		return amntToMint;
	}

	function redeem(address to, uint256 shares) public onlyVault returns (uint256 amntOut) {
		uint256 stratBalance = underlying.balanceOf(lpToken);
		uint256 supply = MockERC20(lpToken).totalSupply();

		MockERC20(lpToken).burn(address(this), shares);
		uint256 amntUnderlying = (shares * stratBalance) / supply;

		MockERC20(address(underlying)).burn(lpToken, amntUnderlying);
		MockERC20(address(underlying)).mint(to, amntUnderlying);
		return amntUnderlying;
	}

	function closePosition(uint256) public onlyVault returns (uint256) {
		uint256 amount = underlying.balanceOf(lpToken);
		MockERC20(lpToken).burn(address(this), amount);
		MockERC20(address(underlying)).burn(lpToken, amount);
		MockERC20(address(underlying)).mint(vault, amount);
		return amount;
	}

	function getAndUpdateTvl() public returns (uint256) {
		return getTvl();
	}

	function getTvl() public view returns (uint256) {
		return underlying.balanceOf(address(lpToken));
	}

	function getMaxTvl() public pure returns (uint256) {
		return type(uint256).max;
	}

	function collateralToUnderlying() public view returns (uint256) {
		uint256 supply = MockERC20(lpToken).totalSupply();
		if (supply == 0) return 1e18;
		uint256 stratBalance = underlying.balanceOf(lpToken);
		return (1e18 * stratBalance) / supply;
	}

	function harvest(HarvestSwapParams[] calldata params, HarvestSwapParams[] calldata)
		public
		override
		onlyVault
		returns (uint256[] memory, uint256[] memory)
	{
		/// simulate harvest profits
		if (params.length > 0) MockERC20(address(underlying)).mint(address(lpToken), params[0].min);
		return (new uint256[](0), new uint256[](0));
	}

	function getLpBalance() public view returns (uint256) {
		return MockERC20(lpToken).balanceOf(address(this));
	}

	function getWithdrawAmnt(uint256 lpTokens) public view returns (uint256) {
		return (lpTokens * collateralToUnderlying()) / 1e18;
	}

	function getDepositAmnt(uint256 uAmnt) public view returns (uint256) {
		return (uAmnt * 1e18) / collateralToUnderlying();
	}
}
