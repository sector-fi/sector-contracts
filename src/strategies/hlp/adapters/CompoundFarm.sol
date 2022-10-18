// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICompound, ICTokenErc20 } from "../../mixins/ICompound.sol";
import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";
import { IFarmable, HarvestSwapParms, IUniswapV2Router01 } from "../../mixins/IFarmable.sol";

// import "hardhat/console.sol";

abstract contract CompoundFarm is ICompound, IFarmable {
	using SafeERC20 for IERC20;

	IUniswapV2Router01 private _router;
	IERC20 _farmToken;

	function __CompoundFarm_init_(address router_, address token_) internal initializer {
		_farmToken = IERC20(token_);
		_router = IUniswapV2Router01(router_);
		_farmToken.safeApprove(address(_router), type(uint256).max);
	}

	function lendFarmRouter() public view override returns (IUniswapV2Router01) {
		return _router;
	}

	function _harvestLending(HarvestSwapParms[] calldata swapParams)
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

		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));
		if (harvested[0] == 0) return harvested;

		if (address(_router) != address(0))
			_swap(_router, swapParams[0], address(_farmToken), harvested[0]);
		emit HarvestedToken(address(_farmToken), harvested[0]);
	}
}
