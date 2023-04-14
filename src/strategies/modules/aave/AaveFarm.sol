// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";
import { IFarmable, HarvestSwapParams, IUniswapV2Router01 } from "../../mixins/IFarmable.sol";
import { ILending } from "../../mixins/ILending.sol";

// import "hardhat/console.sol";

abstract contract AaveFarm is ILending, IFarmable {
	using SafeERC20 for IERC20;

	constructor(address router_, address token_) {}

	function lendFarmRouter() public pure override returns (address) {
		return address(0);
	}

	function _harvestLending(HarvestSwapParams[] calldata swapParams)
		internal
		virtual
		override
		returns (uint256[] memory harvested)
	{}
}
