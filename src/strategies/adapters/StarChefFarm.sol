// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IStarchef } from "../../interfaces/strategies/IStarchef.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";

struct FarmConfig {
	address farm;
	uint16 farmId;
	address router;
	address farmToken;
}

abstract contract StarChefFarm {
	IStarchef public farm;
	uint16 public farmId;
	ISwapRouter public router;
	IERC20 public farmToken;

	constructor(FarmConfig memory farmConfig) {
		farm = IStarchef(farmConfig.farm);
		farmId = farmConfig.farmId;
		router = ISwapRouter(farmConfig.router);
		farmToken = IERC20(farmConfig.farmToken);
		farmToken.approve(address(router), type(uint256).max);
	}

	function _harvest(HarvestSwapParams calldata param)
		internal
		returns (uint256 tokenHarvest, uint256 amountOut)
	{
		farm.deposit(farmId, 0);
		tokenHarvest = farmToken.balanceOf(address(this));
		if (tokenHarvest == 0) return (0, 0);

		if (bytes20(param.pathData) != bytes20(address(farmToken))) {
			revert InvalidPathData();
		}

		ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
			path: param.pathData,
			recipient: address(this),
			deadline: block.timestamp,
			amountIn: tokenHarvest,
			amountOutMinimum: param.min
		});
		amountOut = router.exactInput(swapParams);
	}

	error InvalidPathData();
}
