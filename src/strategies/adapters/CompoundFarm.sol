// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICompound, ICTokenErc20 } from "../mixins/ICompound.sol";
import { IUniswapV2Pair } from "../../interfaces/uniswap/IUniswapV2Pair.sol";
import { IFarmable } from "../mixins/IFarmable.sol";
import { IUniswapV2Router01 } from "../../interfaces/uniswap/IUniswapV2Router01.sol";
import { HarvestSwapParams } from "../mixins/IBase.sol";

// import "hardhat/console.sol";

abstract contract CompoundFarm is ICompound, IFarmable {
	using SafeERC20 for IERC20;

	IUniswapV2Router01 private _router;
	IERC20 _farmToken;

	constructor(address router_, address token_) {
		_farmToken = IERC20(token_);
		_router = IUniswapV2Router01(router_);
		_farmToken.safeApprove(address(_router), type(uint256).max);
	}

	function lendFarmRouter() public view override returns (address) {
		return address(_router);
	}

	function _harvestLending(HarvestSwapParams[] calldata swapParams)
		internal
		virtual
		override
		returns (uint256[] memory harvested)
	{
		// comp token rewards
		ICTokenErc20[] memory cTokens = new ICTokenErc20[](2);
		cTokens[0] = cTokenLend();
		cTokens[1] = cTokenBorrow();
		comptroller().claimComp(address(this), cTokens);

		uint256 farmHarvest = _farmToken.balanceOf(address(this));
		if (farmHarvest == 0) return harvested;

		HarvestSwapParams memory swapParam = swapParams[0];
		_validatePath(address(_farmToken), swapParam.path);

		uint256[] memory amounts = _router.swapExactTokensForTokens(
			harvested[0],
			swapParam.min,
			swapParam.path, // optimal route determined externally
			address(this),
			swapParam.deadline
		);

		harvested = new uint256[](1);
		harvested[0] = amounts[amounts.length - 1];
		emit HarvestedToken(address(_farmToken), harvested[0]);
	}
}
