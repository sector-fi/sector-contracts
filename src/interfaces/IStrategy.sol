// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IStrategy {
	function getAndUpdateTVL() external returns (uint256);

	function getTotalTVL() external view returns (uint256);

	function getTVL()
		external
		view
		returns (
			uint256 tvl,
			uint256 collateralBalance,
			uint256 borrowPosition,
			uint256 borrowBalance,
			uint256 lpBalance,
			uint256 underlyingBalance
		);
}
