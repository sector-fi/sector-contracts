// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDCMock is ERC20 {
	constructor(uint256 initialSupply) ERC20("USDC", "USDC") {
		_mint(msg.sender, initialSupply);
	}
}