// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	uint8 _decimals;

	constructor(
		string memory _name,
		string memory _symbol,
		uint8 decimals_
	) ERC20(_name, _symbol) {
		_decimals = decimals_;
	}

	function decimals() public view override returns (uint8) {
		return _decimals;
	}

	function mint(address to, uint256 value) public virtual {
		_mint(to, value);
	}

	function burn(address from, uint256 value) public virtual {
		_burn(from, value);
	}
}
