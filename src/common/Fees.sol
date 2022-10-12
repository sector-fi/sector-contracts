// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Auth } from "./Auth.sol";

// import "hardhat/console.sol";

abstract contract Fees is Auth {
	using SafeERC20 for IERC20;

	constructor(address _treasury, uint256 _performanceFee) {
		treasury = _treasury;
		performanceFee = _performanceFee;
		emit SetTreasury(_treasury);
		emit SetPerformanceFee(_performanceFee);
	}

	/// @notice Emitted when the fee percentage is updated.
	/// @param performanceFee The new fee percentage.
	event SetPerformanceFee(uint256 performanceFee);

	event SetTreasury(address indexed treasury);

	/// @notice The percentage of profit recognized each harvest to reserve as fees.
	/// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
	uint256 public performanceFee;

	/// @notice The percentage of profit recognized each harvest to reserve as fees.
	/// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
	uint256 public performanceFee;

	address public treasury;

	/// @notice Sets a new performanceFee.
	/// @param _performanceFee The new performance fee.
	function setPerformanceFee(uint256 _performanceFee) public onlyOwner {
		// A fee percentage over 100% doesn't make sense.
		require(_performanceFee <= 1e18, "FEE_TOO_HIGH");

		// Update the fee percentage.
		performanceFee = _performanceFee;
		emit SetPerformanceFee(performanceFee);
	}

	/// @notice Updates treasury.
	/// @param _treasury New treasury address.
	function setTreasury(address _treasury) public onlyOwner {
		treasury = _treasury;
		emit SetTreasury(_treasury);
	}
}
