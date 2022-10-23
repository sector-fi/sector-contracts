// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IBase, HarvestSwapParms } from "./IBase.sol";
import { IFarmable, IUniswapV2Router01 } from "./IFarmable.sol";

// import "hardhat/console.sol";

abstract contract ILending is IBase {
	function _addLendingApprovals() internal virtual;

	function _getCollateralBalance() internal view virtual returns (uint256);

	function _getBorrowBalance() internal view virtual returns (uint256);

	function _updateAndGetCollateralBalance() internal virtual returns (uint256);

	function _updateAndGetBorrowBalance() internal virtual returns (uint256);

	function _getCollateralFactor() internal view virtual returns (uint256);

	function safeCollateralRatio() public view virtual returns (uint256);

	function _oraclePriceOfShort(uint256 amount) internal view virtual returns (uint256);

	function _oraclePriceOfUnderlying(uint256 amount) internal view virtual returns (uint256);

	function _lend(uint256 amount) internal virtual;

	function _redeem(uint256 amount) internal virtual;

	function _borrow(uint256 amount) internal virtual;

	function _repay(uint256 amount) internal virtual;

	function _harvestLending(HarvestSwapParms[] calldata swapParams)
		internal
		virtual
		returns (uint256[] memory);

	function lendFarmRouter() public view virtual returns (IUniswapV2Router01);

	function getCollateralRatio() public view virtual returns (uint256) {
		return (_getCollateralFactor() * safeCollateralRatio()) / 1e18;
	}

	// returns loan health value which is collateralBalance / minCollateral
	function loanHealth() public view returns (uint256) {
		uint256 borrowValue = _oraclePriceOfShort(_getBorrowBalance());
		if (borrowValue == 0) return 100e18;
		uint256 collateralBalance = _getCollateralBalance();
		uint256 minCollateral = (borrowValue * 1e18) / _getCollateralFactor();
		return (1e18 * collateralBalance) / minCollateral;
	}

	function _adjustCollateral(uint256 targetCollateral)
		internal
		returns (uint256 added, uint256 removed)
	{
		uint256 collateralBalance = _getCollateralBalance();
		if (collateralBalance == targetCollateral) return (0, 0);
		(added, removed) = collateralBalance > targetCollateral
			? (uint256(0), _removeCollateral(collateralBalance - targetCollateral))
			: (_addCollateral(targetCollateral - collateralBalance), uint256(0));
	}

	function _removeCollateral(uint256 amountToRemove) internal returns (uint256 removed) {
		uint256 maxRemove = _freeCollateral();
		removed = maxRemove > amountToRemove ? amountToRemove : maxRemove;
		if (removed > 0) _redeem(removed);
	}

	function _freeCollateral() internal view returns (uint256) {
		uint256 collateral = _getCollateralBalance();
		uint256 borrowValue = _oraclePriceOfShort(_getBorrowBalance());
		// stay within 1% of the liquidation threshold (this is allways temporary)
		uint256 minCollateral = (100 * (borrowValue * 1e18)) / _getCollateralFactor() / 99;
		if (minCollateral > collateral) return 0;
		return collateral - minCollateral;
	}

	function _addCollateral(uint256 amountToAdd) internal returns (uint256 added) {
		uint256 underlyingBalance = underlying().balanceOf(address(this));
		added = underlyingBalance > amountToAdd ? amountToAdd : underlyingBalance;
		if (added != 0) _lend(added);
	}

	function _maxBorrow() internal view virtual returns (uint256);
}
