// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HarvestSwapParams } from "../Structs.sol";

interface ISCYStrategy is IERC20 {
	// scy deposit
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountTokenToPull,
		uint256 minSharesOut
	) external payable returns (uint256 amountSharesOut);

	function redeem(
		address receiver,
		uint256 amountSharesToPull,
		address tokenOut,
		uint256 minTokenOut
	) external returns (uint256 amountTokenOut);

	function getAndUpdateTvl() external returns (uint256 tvl);

	function getTvl() external view returns (uint256 tvl);

	function MIN_LIQUIDITY() external view returns (uint256);

	function underlying() external view returns (IERC20);

	function sendERC20ToStrategy() external view returns (bool);

	function strategy() external view returns (address payable);

	function underlyingBalance(address) external view returns (uint256);

	function underlyingToShares(uint256 amnt) external view returns (uint256);

	function exchangeRateUnderlying() external view returns (uint256);

	function sharesToUnderlying(uint256 shares) external view returns (uint256);

	function getUpdatedUnderlyingBalance(address) external returns (uint256);

	function getFloatingAmount(address) external view returns (uint256);

	function getStrategyTvl() external view returns (uint256);

	function acceptsNativeToken() external view returns (bool);

	function underlyingDecimals() external view returns (uint8);

	function getMaxTvl() external view returns (uint256);

	function closePosition(uint256 minAmountOut, uint256 slippageParam) external;

	function initStrategy(address) external;

	function harvest(
		uint256 expectedTvl,
		uint256 maxDelta,
		HarvestSwapParams[] calldata swap1,
		HarvestSwapParams[] calldata swap2
	) external returns (uint256[] memory harvest1, uint256[] memory harvest2);

	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) external;

	function depositIntoStrategy(uint256 amount, uint256 minSharesOut) external;

	function uBalance() external view returns (uint256);
}
