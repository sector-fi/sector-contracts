// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { AuthU } from "./AuthU.sol";

abstract contract TreasuryU is AuthU {
	address public treasury;

	/// @notice Emitted when treasury address is updated.
	/// @param treasury The authorized user who triggered the update.
	event TreasuryUpdated(address indexed treasury);

	/// @notice Sets a new treasury address.
	/// @param _treasury the new treasury address.
	function setTreasury(address _treasury) public onlyOwner {
		treasury = _treasury;
		emit TreasuryUpdated(_treasury);
	}

	// /// @notice Emitted after fees are claimed.
	// /// @param user The authorized user who claimed the fees.
	// /// @param amount The amount of vault that were claimed.
	// event FeesClaimed(address indexed user, uint256 amount);
}
