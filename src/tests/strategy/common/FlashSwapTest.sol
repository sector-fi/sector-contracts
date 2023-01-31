// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { UniswapMixin } from "./UniswapMixin.sol";

abstract contract FlashSwapTest is UniswapMixin {
	function testFlashSwap() public {
		uint256 amnt = getAmnt();

		deposit(user1, amnt);
		uint256 startBalance = vault.underlyingBalance(user1);

		// trackCost();
		uint256 r = 1.5e18;
		moveUniPrice(r);
		deposit(user2, amnt);
		assertApproxEqRel(
			vault.underlyingBalance(user2),
			amnt,
			.002e18, // withthin .001% (slippage)
			"second balance"
		);
		moveUniPrice(1e36 / r);
		uint256 balance = vault.underlyingBalance(user1);
		if (startBalance > balance)
			assertApproxEqRel(
				balance,
				startBalance,
				.001e18,
				"first balance should not decrease segnificantly"
			); // within .1%
	}
}
