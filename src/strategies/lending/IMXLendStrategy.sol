// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../../vaults/ERC5115/SCYStrategy.sol";
import { IPoolToken, IBorrowable } from "../../interfaces/imx/IImpermax.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVault } from "../../vaults/ERC5115/SCYVault.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { AuthConfig, Auth } from "../../common/Auth.sol";
import { FeeConfig, Fees } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { StratAuthLight } from "../../common/StratAuthLight.sol";

// import "hardhat/console.sol";

contract IMXLendStrategy is StratAuthLight {
	using SafeERC20 for IERC20;

	IPoolToken public immutable poolToken;
	IERC20 public immutable underlying;

	constructor(address _poolToken) {
		poolToken = IPoolToken(_poolToken);
		underlying = IERC20(poolToken.underlying());
	}

	function deposit(uint256 amount) public onlyVault returns (uint256) {
		underlying.safeTransfer(address(poolToken), amount);
		return poolToken.mint(address(this));
	}

	function redeem(address to, uint256 amount) public onlyVault returns (uint256 amountOut) {
		IERC20(address(poolToken)).safeTransfer(address(poolToken), amount);
		amountOut = poolToken.redeem(to);
		return amountOut;
	}

	function getAndUpdateTvl() external returns (uint256) {
		// exchange rate does the accrual
		uint256 exchangeRate = IBorrowable(address(poolToken)).exchangeRate();
		uint256 balance = IERC20(address(poolToken)).balanceOf(address(this));
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function getTvl() external view returns (uint256) {
		uint256 balance = IERC20(address(poolToken)).balanceOf(address(this));
		uint256 exchangeRate = IBorrowable(address(poolToken)).exchangeRateLast();
		uint256 underlyingBalance = (balance * exchangeRate) / 1e18;
		return underlyingBalance;
	}

	function closePosition(uint256) external onlyVault returns (uint256) {
		uint256 yeildTokenAmnt = IERC20(address(poolToken)).balanceOf(address(this));
		IERC20(address(poolToken)).safeTransfer(address(poolToken), yeildTokenAmnt);
		return IPoolToken(poolToken).redeem(address(this));
	}

	// TOOD fraction of total deposits
	function maxTvl() internal pure returns (uint256) {
		return type(uint256).max;
	}

	function collateralToUnderlying() internal view returns (uint256) {
		return IBorrowable(address(poolToken)).exchangeRateLast();
	}

	function harvest(HarvestSwapParams[] calldata params)
		internal
		returns (uint256[] memory harvest1, uint256[] memory harvest2)
	{}
}
