// License-Identifier: MIT
pragma solidity ^0.8.6;

struct PoolInfo {
	address lpToken; // Address of LP token contract.
	uint256 allocPoint; // How many allocation points assigned to this pool. STGs to distribute per block.
	uint256 lastRewardBlock; // Last block number that STGs distribution occurs.
	uint256 accStargatePerShare; // Accumulated STGs per share, times 1e12. See below.
}

interface IStarchef {
	struct UserInfo {
		uint256 amount;
		uint256 rewardDebt;
	}

	function stargate() external view returns (address);

	function poolLength() external view returns (uint256);

	function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

	function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

	function deposit(uint256 pid, uint256 amount) external;

	function withdraw(uint256 pid, uint256 amount) external;

	function pendingStargate(uint256 _pid, address _user) external view returns (uint256);
}
