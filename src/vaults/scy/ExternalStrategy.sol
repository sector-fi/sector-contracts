// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, Initializable, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { SCYVault } from "./SCYVault.sol";

abstract contract ExternalStrategy is SCYVault {
	using SafeERC20 for IERC20;

	// send funds to strategy
	function _transferIn(
		uint96 id,
		address token,
		address from,
		uint256 amount
	) internal override {
		if (token == NATIVE) {
			// if strategy logic lives in this contract, don't do anything
			address stratAddr = strategies[id].addr;
			if (stratAddr == address(this))
				return SafeETH.safeTransferETH(strategies[id].addr, amount);
		} else IERC20(token).safeTransferFrom(from, strategies[id].addr, amount);
	}

	// send funds to user
	function _transferOut(
		uint96 id,
		address token,
		address to,
		uint256 amount
	) internal override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransferFrom(strategies[id].addr, to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(uint96 id, address token) internal view override returns (uint256) {
		return
			(token == NATIVE)
				? strategies[id].addr.balance
				: IERC20(token).balanceOf(strategies[id].addr);
	}
}
