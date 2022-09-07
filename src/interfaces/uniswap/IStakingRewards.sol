// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStakingRewards is IERC20 {
	function stakingToken() external view returns (address);

	function lastTimeRewardApplicable() external view returns (uint256);

	function rewardPerToken() external view returns (uint256);

	function earned(address account) external view returns (uint256);

	function getRewardForDuration() external view returns (uint256);

	function stakeWithPermit(
		uint256 amount,
		uint256 deadline,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external;

	function stake(uint256 amount) external;

	function withdraw(uint256 amount) external;

	function getReward() external;

	function exit() external;
}

// some farms use sushi interface
interface IMasterChef {
	// depositing 0 amount will withdraw the rewards (harvest)
	function deposit(uint256 _pid, uint256 _amount) external;

	function withdraw(uint256 _pid, uint256 _amount) external;

	function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);

	function emergencyWithdraw(uint256 _pid) external;

	function pendingTokens(uint256 _pid, address _user)
		external
		view
		returns (
			uint256,
			address,
			string memory,
			uint256
		);
}

interface IMiniChefV2 {
	struct UserInfo {
		uint256 amount;
		int256 rewardDebt;
	}

	struct PoolInfo {
		uint128 accSushiPerShare;
		uint64 lastRewardTime;
		uint64 allocPoint;
	}

	function poolLength() external view returns (uint256);

	function updatePool(uint256 pid) external returns (IMiniChefV2.PoolInfo memory);

	function userInfo(uint256 _pid, address _user) external view returns (uint256, int256);

	function deposit(
		uint256 pid,
		uint256 amount,
		address to
	) external;

	function withdraw(
		uint256 pid,
		uint256 amount,
		address to
	) external;

	function harvest(uint256 pid, address to) external;

	function withdrawAndHarvest(
		uint256 pid,
		uint256 amount,
		address to
	) external;

	function emergencyWithdraw(uint256 pid, address to) external;
}
