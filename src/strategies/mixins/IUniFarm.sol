// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IBase, HarvestSwapParams } from "./IBase.sol";
import { IUniLp, SafeERC20, IERC20 } from "./IUniLp.sol";
import { IFarmable, IUniswapV2Router01 } from "./IFarmable.sol";

// import "hardhat/console.sol";

abstract contract IUniFarm is IBase, IUniLp, IFarmable {
	function _depositIntoFarm(uint256 amount) internal virtual;

	function _withdrawFromFarm(uint256 amount) internal virtual;

	function _harvestFarm(HarvestSwapParams[] calldata swapParams)
		internal
		virtual
		returns (uint256[] memory);

	function _getFarmLp() internal view virtual returns (uint256);

	function _addFarmApprovals() internal virtual;

	function farmRouter() public view virtual returns (address);
}
