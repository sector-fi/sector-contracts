// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IClaimReward } from "../../../interfaces/compound/IClaimReward.sol";
import { CompoundFarm, HarvestSwapParams } from "./CompoundFarm.sol";
import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";

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
		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));

		if (harvested[0] > 0) {
			_swap(lendFarmRouter(), swapParams[0], address(_farmToken), harvested[0]);
			emit HarvestedToken(address(_farmToken), harvested[0]);
		}

		// base token rewards on id 1
		IClaimReward(address(comptroller())).claimReward(1, payable(address(this)));

		uint256 avaxBalance = address(this).balance;
		if (avaxBalance > 0) {
			IWETH(address(short())).deposit{ value: avaxBalance }();
			emit HarvestedToken(address(short()), avaxBalance);
		}
	}
}
