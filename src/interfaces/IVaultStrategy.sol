// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { VaultType } from "./Structs.sol";

interface IVaultStrategy is IERC20 {
	// scy deposit
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountTokenToPull,
		uint256 minSharesOut
	) external payable returns (uint256 amountSharesOut);

	// erc4626 deposit
	function deposit(uint256 amount, address to) external payable returns (uint256 amountSharesOut);

	function vaultType() external view returns (VaultType);

	function redeem(
		address receiver,
		uint256 amountSharesToPull,
		address tokenOut,
		uint256 minTokenOut
	) external returns (uint256 amountTokenOut);

	function symbol() external returns (string memory);

	function requestRedeem(uint256 shares) external;

	function redeem() external returns (uint256 amountTokenOut);

	function getAndUpdateTvl() external returns (uint256 tvl);

	function getTvl() external view returns (uint256 tvl);

	function getMaxTvl() external view returns (uint256);

	function MIN_LIQUIDITY() external view returns (uint256);

	function underlying() external view returns (IERC20);

	function sendERC20ToStrategy() external view returns (bool);

	function strategy() external view returns (address payable);

	function underlyingBalance(address) external view returns (uint256);

	function underlyingToShares(uint256 amnt) external view returns (uint256);

	function exchangeRateUnderlying() external view returns (uint256);

	function sharesToUnderlying(uint256 shares) external view returns (uint256);

	function getUpdatedUnderlyingBalance(address) external returns (uint256);

	// only for withdraw batch vaults
	function requestedRedeem() external view returns (uint256);

	/// @dev slippage param is optional
	function processRedeem(uint256 slippageParam) external;
}
