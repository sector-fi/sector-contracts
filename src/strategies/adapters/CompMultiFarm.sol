// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IClaimReward } from "../../interfaces/compound/IClaimReward.sol";
import { CompoundFarm, HarvestSwapParams, IUniswapV2Router01 } from "./CompoundFarm.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

abstract contract CompMultiFarm is CompoundFarm {
	// BenQi has two two token rewards
	// pid 0 is Qi token and pid 1 is AVAX (not wrapped)
	function _harvestLending(HarvestSwapParams[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		// farm token on id 0
		IClaimReward(address(comptroller())).claimReward(0, payable(address(this)));
		uint256 farmHarvest = _farmToken.balanceOf(address(this));

		if (farmHarvest > 0) {
			uint256[] memory amounts = _swap(
				IUniswapV2Router01(lendFarmRouter()),
				swapParams[0],
				address(_farmToken),
				farmHarvest
			);
			harvested = new uint256[](1);
			harvested[0] = amounts[amounts.length - 1];
			emit HarvestedToken(address(_farmToken), harvested[0]);
		}

		// base token rewards on id 1
		IClaimReward(address(comptroller())).claimReward(1, payable(address(this)));

		uint256 nativeBalance = address(this).balance;
		if (nativeBalance > 0) {
			IWETH(address(short())).deposit{ value: nativeBalance }();
			emit HarvestedToken(address(short()), nativeBalance);
		}
	}
}
