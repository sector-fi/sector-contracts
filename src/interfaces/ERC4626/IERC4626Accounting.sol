// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

interface IERC4626Accounting {
	function totalAssets() external view returns (uint256);

	function convertToShares(uint256 assets) external view returns (uint256);

	function convertToAssets(uint256 shares) external view returns (uint256);

	function previewDeposit(uint256 assets) external view returns (uint256);

	function previewMint(uint256 shares) external view returns (uint256);

	function previewWithdraw(uint256 assets) external view returns (uint256);

	function previewRedeem(uint256 shares) external view returns (uint256);
}
