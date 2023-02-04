// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { IERC20 } from "./SCYBase.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { SectorErrors } from "../../interfaces/SectorErrors.sol";

struct SCYVaultConfig {
	string symbol;
	string name;
	address addr;
	uint16 strategyId; // this is strategy specific token if 1155
	bool acceptsNativeToken;
	address yieldToken;
	IERC20 underlying;
	uint128 maxTvl; // pack all params and balances
	uint128 balance; // strategy balance in underlying
	uint128 uBalance; // underlying balance
	uint128 yBalance; // yield token balance
}

interface ISCYStrategy {
	function deposit(uint256 amount) external returns (uint256);

	function redeem(address to, uint256 amount) external returns (uint256 amntOut);

	function closePosition(uint256 slippageParam) external returns (uint256);

	function getAndUpdateTvl() external returns (uint256);

	function getTvl() external view returns (uint256);

	function maxTvl() external view returns (uint256);

	function collateralToUnderlying() external view returns (uint256);

	function harvest(
		HarvestSwapParams[] calldata farm1Params,
		HarvestSwapParams[] calldata farm2Parms
	) external returns (uint256[] memory harvest1, uint256[] memory harvest2);

	function getWithdrawAmnt(uint256 lpTokens) external view returns (uint256);

	function getDepositAmnt(uint256 uAmnt) external view returns (uint256);
}
