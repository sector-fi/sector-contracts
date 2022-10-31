// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IMiniChefV2 } from "../../interfaces/uniswap/IStakingRewards.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";

// import "hardhat/console.sol";
struct FarmConfig {
	address farm;
	uint16 farmId;
	address router;
	address farmToken;
}

abstract contract MiniChef2Farm {
	using SafeERC20 for IERC20;

	IMiniChefV2 public farm;
	ISwapRouter public farmRouter;
	IERC20 public farmToken;
	uint256 public farmId;

	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);

	constructor(FarmConfig memory farmConfig) {
		farm = IMiniChefV2(farmConfig.farm);
		farmRouter = ISwapRouter(farmConfig.router);
		farmToken = IERC20(farmConfig.farmToken);
		farmId = farmConfig.farmId;
		farmToken.safeApprove(address(farmRouter), type(uint256).max);
	}

	function _withdrawFromFarm(uint256 amount) internal {
		farm.withdraw(farmId, amount, address(this));
	}

	function _depositIntoFarm(uint256 amount) internal {
		farm.deposit(farmId, amount, address(this));
	}

	function _getFarmLp() internal view returns (uint256 lp) {
		(lp, ) = farm.userInfo(farmId, address(this));
	}

	function _harvestFarm(HarvestSwapParams calldata swapParams)
		internal
		returns (uint256 harvested, uint256 amountOut)
	{
		farm.harvest(farmId, address(this));
		harvested = farmToken.balanceOf(address(this));
		if (harvested == 0) return (0, 0);

		ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
			path: swapParams.pathData,
			recipient: address(this),
			deadline: block.timestamp,
			amountIn: harvested,
			amountOutMinimum: swapParams.min
		});
		amountOut = farmRouter.exactInput(params);
		emit HarvestedToken(address(farmToken), harvested, amountOut);
	}
}
