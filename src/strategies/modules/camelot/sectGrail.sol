// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract sectGrail is ERC20Upgradeable {
	constructor() {}

	function initialize() public initializer {
		__ERC20_init("sectGRAIL", "sectGRAIL");
	}

	function mint(address to, uint256 amount) public {
		_mint(to, amount);
	}
}
