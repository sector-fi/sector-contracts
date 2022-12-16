// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import { IBorrowable, ICollateral, IImpermaxChef } from "../../../interfaces/imx/IImpermax.sol";
import { FarmConfig } from "../../../interfaces/Structs.sol";
import { IBaseU, HarvestSwapParams } from "./IBaseU.sol";
import { IUniLpU, IUniswapV2Pair, SafeERC20, IERC20 } from "./IUniLpU.sol";
import { IFarmableU, IUniswapV2Router01 } from "./IFarmableU.sol";

abstract contract IIMXFarmU is IBaseU, IFarmableU, IUniLpU {
	function loanHealth() public view virtual returns (uint256);

	function sBorrowable() public view virtual returns (IBorrowable);

	function uBorrowable() public view virtual returns (IBorrowable);

	function collateralToken() public view virtual returns (ICollateral);

	function impermaxChef() public view virtual returns (IImpermaxChef);

	function pendingHarvest() external view virtual returns (uint256 harvested);

	function farm() external view virtual returns (IImpermaxChef);

	function farmToken() external view virtual returns (IImpermaxChef);

	function farmRouter() external view virtual returns (IUniswapV2Router01);

	function _getBorrowBalances()
		internal
		view
		virtual
		returns (uint256 underlyingAmnt, uint256 shortAmnt);

	function _updateAndGetBorrowBalances()
		internal
		virtual
		returns (uint256 underlyingAmnt, uint256 shortAmnt);

	function _optimalUBorrow() internal view virtual returns (uint256 uBorrow);

	function _harvestFarm(HarvestSwapParams calldata swapParams) internal virtual returns (uint256);

	function safetyMarginSqrt() public view virtual returns (uint256);

	function accrueInterest() public virtual;

	function _addIMXLiquidity(
		uint256 underlyingAmnt,
		uint256 shortAmnt,
		uint256 uBorrow,
		uint256 sBorrow
	) internal virtual;

	function _removeIMXLiquidity(
		uint256 removeLp,
		uint256 repayUnderlying,
		uint256 repayShort
	) internal virtual;

	function shortToUnderlyingOracleUpdate(uint256 amount) public virtual returns (uint256);

	function shortToUnderlyingOracle(uint256 amount) public view virtual returns (uint256);

	function _configureFarm(FarmConfig memory farmConfig) internal virtual;
}
