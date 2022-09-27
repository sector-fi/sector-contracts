// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (governance/TimelockController.sol)

pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract SectorRegistry is Ownable {
	event AddVault(address vault);

	constructor() Ownable() {}

	function addVault(address vault) public onlyOwner {
		emit AddVault(vault);
	}
}
