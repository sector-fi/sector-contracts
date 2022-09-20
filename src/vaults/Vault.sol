// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Bank } from "../bank/Bank.sol";
import { ERC4626 } from "./ERC4626/ERC4626.sol";

// import "hardhat/console.sol";

contract VaultUpgradable is ERC4626 {
	constructor(
		ERC20 _asset,
		Bank _bank,
		uint256 _managementFee,
		address _owner,
		address _guardian,
		address _manager
	) ERC4626(_asset, _bank, _managementFee, _owner, _guardian, _manager) {}

	// we may not need locked profit depending on how we handle withdrawals
	// normally it is used to gradually release recent harvest rewards in order to avoid
	// front running harvests (deposit immediately before harvest and withdraw immediately after)
	function lockedProfit() public pure override returns (uint256) {
		return 0;
	}

	function totalAssets() public view override returns (uint256) {
		return asset.balanceOf(address(this));
	}
}
