// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { INFTPool } from "./INFTPool.sol";
import { IXGrailToken } from "./IXGrailToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISectGrail {
	function xGrailToken() external view returns (IXGrailToken);

	function grailToken() external view returns (IERC20);

	function whitelist(address contractAddr) external view returns (bool);

	function updateWhitelist(address contractAddr, bool isWhitelisted) external;

	function depositIntoFarm(
		INFTPool _farm,
		uint256 amount,
		uint256 positionId,
		address lp
	) external returns (uint256);

	function withdrawFromFarm(
		INFTPool _farm,
		uint256 amount,
		uint256 positionId,
		address lp
	) external returns (uint256);

	function harvestFarm(INFTPool _farm, uint256 positionId)
		external
		returns (uint256[] memory harvested);

	function allocate(
		address usageAddress,
		uint256 amount,
		bytes memory usageData
	) external;

	function deallocateFromPosition(
		INFTPool _farm,
		uint256 amount,
		uint256 positionId
	) external;

	function getFarmLp(INFTPool _farm, uint256 positionId) external view returns (uint256);

	function getNonAllocatedBalance(address user) external view returns (uint256);

	function getAllocations(address user) external view returns (uint256);

	///////
	/// EVENTS
	////

	event DepositIntoFarm(
		address indexed user,
		address indexed farm,
		uint256 indexed positionId,
		uint256 amount
	);

	event WithdrawFromFarm(
		address indexed user,
		address indexed farm,
		uint256 indexed positionId,
		uint256 amount
	);

	event HarvestFarm(
		address indexed user,
		address indexed farm,
		uint256 indexed positionId,
		uint256[] harvested
	);

	event Allocate(
		address indexed user,
		address indexed usageAddress,
		uint256 amount,
		bytes usageData
	);

	event Deallocate(
		address indexed user,
		address indexed usageAddress,
		uint256 amount,
		bytes usageData
	);

	event UpdateWhitelist(address indexed contractAddr, bool isWhitelisted);
}
