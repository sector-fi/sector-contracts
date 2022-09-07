// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { HarvestSwapParms } from "../../../interfaces/Structs.sol";

abstract contract IBaseU {
	function short() public view virtual returns (IERC20);

	function underlying() public view virtual returns (IERC20);
}
