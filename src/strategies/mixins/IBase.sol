// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";

// all interfaces need to inherit from base
abstract contract IBase {
	function short() public view virtual returns (IERC20);

	function underlying() public view virtual returns (IERC20);
}
