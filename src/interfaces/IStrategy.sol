// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

struct AuthConfig {
	address owner;
	address guardian;
	address manager;
}

struct HarvestSwapParams {
	address[] path;
	uint256 min;
	uint256 deadline;
}

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

	function getLPBalances() external returns (uint256, uint256);

	function vault() external returns (address);

	function decimals() external returns (uint8);

	function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

	function GUARDIAN() external view returns (bytes32);

	function MANAGER() external view returns (bytes32);

	function acceptOwnership() external;

	function accrueInterest() external;

	function closePosition() external returns (uint256 balance);

	function collateralToUnderlying() external view returns (uint256);

	function collateralToken() external view returns (address);

	function deposit(uint256 underlyingAmnt) external returns (uint256);

	function emergencyWithdraw(address recipient, address[] memory tokens) external;

	function farmRouter() external view returns (address);

	function getExpectedPrice() external view returns (uint256);

	function getLiquidity() external view returns (uint256);

	function getMaxTvl() external view returns (uint256);

	function getPositionOffset() external view returns (uint256 positionOffset);

	function getRoleAdmin(bytes32 role) external view returns (bytes32);

	function getUnderlyingShortReserves()
		external
		view
		returns (uint256 reserveA, uint256 reserveB);

	function grantRole(bytes32 role, address account) external;

	function harvest(HarvestSwapParams memory harvestParams) external returns (uint256 farmHarvest);

	function hasRole(bytes32 role, address account) external view returns (bool);

	function loanHealth() external view returns (uint256);

	function maxPriceOffset() external view returns (uint256);

	function owner() external view returns (address);

	function pair() external view returns (address);

	function pendingHarvest() external view returns (uint256 harvested);

	function pendingOwner() external view returns (address);

	function rebalance(uint256 expectedPrice, uint256 maxDelta) external;

	function rebalanceThreshold() external view returns (uint16);

	function redeem(uint256 removeCollateral, address recipient)
		external
		returns (uint256 amountTokenOut);

	function renounceRole(bytes32 role, address account) external;

	function revokeRole(bytes32 role, address account) external;

	function setMaxPriceOffset(uint256 _maxPriceOffset) external;

	function getMaxDeposit() external returns (uint256);

	function setRebalanceThreshold(uint16 rebalanceThreshold_) external;

	function short() external view returns (address);

	function underlying() external view returns (address);

	error NotPaused();
	error LowLoanHealth();
	error OverMaxPriceOffset();
	error RebalanceThreshold();
	error SlippageExceeded();
}
