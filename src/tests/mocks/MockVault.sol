// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { IBank } from "../../bank/IBank.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockVault {
	using SafeERC20 for IERC20;

	IBank bank;

	address[] pools;

	constructor(IBank _bank) {
		bank = _bank;
	}

	function deposit(
		uint96 id,
		address account,
		uint256 amount
	) public {
		IERC20 token = IERC20(pools[id]);
		token.safeTransferFrom(msg.sender, address(this), amount);
		uint256 totalBalance = token.balanceOf(address(this));
		bank.deposit(id, account, amount, totalBalance);
	}

	function withdraw(
		uint96 id,
		address account,
		uint256 amount
	) public {
		IERC20 token = IERC20(pools[id]);
		token.safeTransfer(account, amount);
		uint256 totalBalance = token.balanceOf(address(this));
		bank.withdraw(id, msg.sender, amount, totalBalance);
	}

	function addPool(address token) public {
		require(pools.length < type(uint96).max - 2, "MockVault: Too many pools");
		pools.push(token);
	}
}
