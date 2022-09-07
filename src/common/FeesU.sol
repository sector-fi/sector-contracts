// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { AuthU } from "./AuthU.sol";

// import "hardhat/console.sol";

abstract contract FeesU is AuthU {
	using SafeERC20 for IERC20;

	/// @notice The percentage of profit recognized each harvest to reserve as fees.
	/// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
	uint256 public feePercent;

	/// @notice Emitted when the fee percentage is updated.
	/// @param user The authorized user who triggered the update.
	/// @param newFeePercent The new fee percentage.
	event FeePercentUpdated(address indexed user, uint256 newFeePercent);

	/// @notice Sets a new fee percentage.
	/// @param newFeePercent The new fee percentage.
	function setFeePercent(uint256 newFeePercent) public onlyOwner {
		// A fee percentage over 100% doesn't make sense.
		require(newFeePercent <= 1e18, "FEE_TOO_HIGH");

		// Update the fee percentage.
		feePercent = newFeePercent;

		emit FeePercentUpdated(msg.sender, newFeePercent);
	}

	/// @notice Emitted after fees are claimed.
	/// @param user The authorized user who claimed the fees.
	/// @param amount The amount of vault that were claimed.
	event FeesClaimed(address indexed user, uint256 amount);

	/// @notice Claims fees accrued from harvests.
	/// @param amount The amount of vault tokens to claim.
	/// @dev Accrued fees are measured as rvTokens held by the Vault.
	function claimFees(uint256 amount) external onlyRole("MANAGER") {
		emit FeesClaimed(msg.sender, amount);

		// Transfer the provided amount of rvTokens to the caller.
		IERC20(address(this)).safeTransfer(msg.sender, amount);
	}

	uint256[50] private __gap;
}
