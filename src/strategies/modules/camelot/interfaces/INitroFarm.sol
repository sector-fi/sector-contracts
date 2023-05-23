// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface INitroFarm {
	function rewardsToken1()
		external
		view
		returns (
			address token,
			uint256 amount,
			uint256 remainingAmount,
			uint256 accRewardsPerShare
		);

	function rewardsToken2()
		external
		view
		returns (
			address token,
			uint256 amount,
			uint256 remainingAmount,
			uint256 accRewardsPerShare
		);
}
