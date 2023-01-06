// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { UniswapMixin } from "./UniswapMixin.sol";

abstract contract FlashSwapTest is UniswapMixin {
	function testFlashSwap() public {
		uint256 amnt = getAmnt();

		deposit(user1, amnt);
		uint256 startBalance = vault.underlyingBalance(user1);

		// trackCost();
		moveUniPrice(1.5e18);
		deposit(user2, amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(user2),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		moveUniPrice(.666e18);
		uint256 balance = vault.underlyingBalance(user1);
		assertGe(balance, startBalance, "first balance should not decrease"); // within .1%
	}
}
