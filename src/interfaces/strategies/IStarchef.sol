// License-Identifier: MIT
pragma solidity ^0.8.6;

interface IStarchef {
	struct UserInfo {
		uint256 amount;
		uint256 rewardDebt;
	}

	function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

	function deposit(uint256 pid, uint256 amount) external;

	function withdraw(uint256 pid, uint256 amount) external;

	function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
}
