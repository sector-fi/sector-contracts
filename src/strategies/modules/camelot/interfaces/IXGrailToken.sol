// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IXGrailToken is IERC20 {
	function usageAllocations(address userAddress, address usageAddress)
		external
		view
		returns (uint256 allocation);

	function allocateFromUsage(address userAddress, uint256 amount) external;

	function convertTo(uint256 amount, address to) external;

	function deallocateFromUsage(address userAddress, uint256 amount) external;

	function isTransferWhitelisted(address account) external view returns (bool);

	function redeem(uint256 amount, uint256 duration) external;

	function minRedeemDuration() external view returns (uint256);

	function maxRedeemDuration() external view returns (uint256);

	function getUserRedeemsLength(address userAddress) external view returns (uint256);

	function getUserRedeem(address userAddress, uint256 index)
		external
		view
		returns (
			uint256 grailAmount,
			uint256 xGrailAmount,
			uint256 endTime,
			uint256 timestamp,
			address dividendsContract,
			uint256 dividendsAllocation
		);

	function allocate(
		address userAddress,
		uint256 amount,
		bytes calldata usageData
	) external;

	function deallocate(
		address userAddress,
		uint256 amount,
		bytes calldata usageData
	) external;

	function approveUsage(address usage, uint256 amount) external;
}
