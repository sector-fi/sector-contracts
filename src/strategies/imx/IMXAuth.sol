// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { SafeETH } from "../../libraries/SafeETH.sol";

import { Auth } from "../../common/Auth.sol";

// import "hardhat/console.sol";

abstract contract IMXAuth is Auth {
	using SafeERC20 for IERC20;

	address public vault;

	modifier onlyVault() {
		require(msg.sender == vault, "Strat: ONLY_VAULT");
		_;
	}

	event EmergencyWithdraw(address indexed recipient, IERC20[] tokens);

	// emergency only - send stuck tokens to the owner
	// TODO make arbitrary calls from owner?
	function emergencyWithdraw(address recipient, IERC20[] calldata tokens)
		external
		onlyRole(GUARDIAN)
	{
		for (uint256 i = 0; i < tokens.length; i++) {
			IERC20 token = tokens[i];
			uint256 balance = token.balanceOf(address(this));
			if (balance != 0) token.safeTransfer(recipient, balance);
		}
		if (address(this).balance > 0) SafeETH.safeTransferETH(recipient, address(this).balance);
		emit EmergencyWithdraw(recipient, tokens);
	}

	uint256[50] private __gap;
}
