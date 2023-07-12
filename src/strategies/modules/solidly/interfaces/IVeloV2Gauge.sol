// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

interface IVeloV2Gauge {
	function notifyRewardAmount(uint256 amount) external;

	function getReward(address account) external;

	function left() external view returns (uint256);

	function isPool() external view returns (bool);

	function earned(address account) external view returns (uint256);

	function balanceOf(address account) external view returns (uint256);

	function deposit(uint256 amount) external;

	function withdraw(uint256 amount) external;
}
