// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { EAction, HarvestSwapParams } from "../../interfaces/Structs.sol";
// import "hardhat/console.sol";

struct LevConvexConfig {
	address curveAdapter;
	address convexRewardPool;
	address creditFacade;
	uint16 coinId;
	address underlying;
	uint16 leverageFactor;
	address convexBooster;
	address farmRouter;
}

interface ILevConvex {
	/// @notice deposits underlying into the strategy
	/// @param amount amount of underlying to deposit
	function deposit(uint256 amount) external returns (uint256);

	/// @notice deposits underlying into the strategy
	/// @param amount amount of lp to withdraw
	function redeem(uint256 amount, address to) external returns (uint256);

	function harvest(HarvestSwapParams[] memory swapParams)
		external
		returns (uint256[] memory amountsOut);

	function closePosition() external returns (uint256);

	/// VIEW METHODS

	function getMaxTvl() external view returns (uint256);

	// this is actually not totally accurate
	function collateralToUnderlying() external view returns (uint256);

	function collateralBalance() external view returns (uint256);

	/// @dev gearbox accounting is overly concervative so we use calc_withdraw_one_coin
	/// to compute totalAsssets
	function getTotalTVL() external view returns (uint256);

	function getAndUpdateTVL() external view returns (uint256);

	function underlying() external view returns (address);

	function convexRewardPool() external view returns (address);

	event SetVault(address indexed vault);
	event AdjustLeverage(uint256 newLeverage);
	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);
	event Deposit(address sender, uint256 amount);
	event Redeem(address sender, uint256 amount);

	error WrongVaultUnderlying();
}
