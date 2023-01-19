// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IWETH } from "../interfaces/uniswap/IWETH.sol";
import { SafeETH } from "../libraries/SafeETH.sol";
import { Accounting } from "./Accounting.sol";
import { SectorErrors } from "../interfaces/SectorErrors.sol";
import { EpochType } from "../interfaces/Structs.sol";

// import "hardhat/console.sol";

struct WithdrawRecord {
	uint256 timestamp;
	uint256 shares;
	uint256 value; // this the current value (also max withdraw value)
}

abstract contract BatchedWithdraw is ERC20, Accounting, SectorErrors {
	using SafeERC20 for ERC20;

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	uint256 public lastHarvestTimestamp;
	uint256 public requestedRedeem;
	uint256 public pendingRedeem;

	EpochType public constant epochType = EpochType.None;

	mapping(address => WithdrawRecord) public withdrawLedger;

	function requestRedeem(uint256 shares) public {
		return requestRedeem(shares, msg.sender);
	}

	function requestRedeem(uint256 shares, address owner) public {
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
		_requestRedeem(shares, owner, msg.sender);
	}

	/// @dev redeem request records the value of the redeemed shares at the time of request
	/// at the time of claim, user is able to withdraw the minimum of the
	/// current value and value at time of request
	/// this is to prevent users from pre-emptively submitting redeem claims
	/// and claiming any rewards after the request has been made
	function _requestRedeem(
		uint256 shares,
		address owner,
		address redeemer
	) internal {
		_transfer(owner, address(this), shares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[redeemer];
		withdrawRecord.timestamp = block.timestamp;
		withdrawRecord.shares += shares;
		uint256 value = convertToAssets(shares);
		withdrawRecord.value += value;
		requestedRedeem += shares;
		emit RequestWithdraw(msg.sender, owner, shares);
	}

	function _redeem(address account) internal returns (uint256 amountOut, uint256 shares) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[account];

		if (withdrawRecord.value == 0) revert ZeroAmount();
		if (withdrawRecord.timestamp >= lastHarvestTimestamp) revert NotReady();

		shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;

		// actual amount out is the smaller of currentValue and redeemValue
		amountOut = _getWithdrawAmount(shares, redeemValue);

		// update total pending redeem
		pendingRedeem -= shares;

		// important pendingRedeem should update prior to beforeWithdraw call
		withdrawRecord.value = 0;
		withdrawRecord.shares = 0;
	}

	function _processRedeem() internal {
		pendingRedeem += requestedRedeem;
		requestedRedeem = 0;
	}

	function _getWithdrawAmount(uint256 shares, uint256 redeemValue)
		internal
		view
		returns (uint256 amountOut)
	{
		// value of shares at time of redemption request
		uint256 currentValue = convertToAssets(shares);
		// actual amount out is the smaller of currentValue and redeemValue
		amountOut = currentValue < redeemValue ? currentValue : redeemValue;
	}

	function cancelRedeem() public virtual {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		if (withdrawRecord.timestamp <= lastHarvestTimestamp) revert CannotCancelProccesedRedeem();

		uint256 shares = withdrawRecord.shares;

		// update accounting
		withdrawRecord.value = 0;
		withdrawRecord.shares = 0;
		requestedRedeem -= shares;

		return _transfer(address(this), msg.sender, shares);
	}

	/// @notice UI method to view cancellation penalty
	function getPenalty() public view returns (uint256) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		uint256 shares = withdrawRecord.shares;

		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		if (currentValue < redeemValue) return 0;
		return (1e18 * (currentValue - redeemValue)) / redeemValue;
	}

	/// UTILS
	function redeemIsReady(address user) external view returns (bool) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[user];
		return lastHarvestTimestamp > withdrawRecord.timestamp && withdrawRecord.value > 0;
	}

	function getWithdrawStatus(address user) external view returns (WithdrawRecord memory) {
		return withdrawLedger[user];
	}

	error NotReady();
	error CannotCancelProccesedRedeem();
	error NotNativeAsset();
}
