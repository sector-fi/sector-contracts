// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "./ERC4626.sol";

import "hardhat/console.sol";

struct WithdrawRecord {
	uint256 timestamp;
	uint256 shares;
	uint256 value; // this the current value (also max withdraw value)
}

abstract contract BatchedWithdraw is ERC4626 {
	using SafeERC20 for ERC20;

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	uint256 public withdrawTimestamp;
	uint256 public pendingWithdraw; // actual amount may be less

	mapping(address => WithdrawRecord) public withdrawLedger;

	function requestRedeem(uint256 shares) public {
		return requestRedeem(shares, msg.sender);
	}

	function requestRedeem(uint256 shares, address owner) public {
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
		_transfer(owner, address(this), shares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		withdrawRecord.timestamp = block.timestamp;
		withdrawRecord.shares += shares;
		uint256 value = convertToAssets(shares);
		withdrawRecord.value = value;
		pendingWithdraw += value;
		emit RequestWithdraw(msg.sender, owner, shares);
	}

	function withdraw(
		uint256,
		address,
		address
	) public pure virtual override returns (uint256) {
		revert NotImplemented();
	}

	function redeem(
		uint256,
		address receiver,
		address
	) public virtual override returns (uint256 amountOut) {
		return redeem(receiver);
	}

	/// @dev safest UI method
	function redeem() public virtual returns (uint256 amountOut) {
		return redeem(msg.sender);
	}

	function redeem(address receiver) public virtual returns (uint256 amountOut) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		if (withdrawRecord.value == 0) revert ZeroAmount();
		if (withdrawRecord.timestamp > withdrawTimestamp) revert NotReady();

		uint256 shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		// actual amount out is the smaller of currentValue and redeemValue
		amountOut = currentValue < redeemValue ? currentValue : redeemValue;

		// update total pending withdraw
		pendingWithdraw -= redeemValue;

		// important pendingWithdraw should update prior to beforeWithdraw call
		beforeWithdraw(amountOut, shares);
		withdrawRecord.value = 0;
		_burn(address(this), shares);
		ERC20(asset).transfer(receiver, amountOut);
		emit Withdraw(msg.sender, receiver, owner, amountOut, shares);
	}

	function cancelRedeem() public virtual {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];

		uint256 shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		// update accounting
		withdrawRecord.value = 0;
		pendingWithdraw -= redeemValue;

		// if vault lost money, shares stay the same
		if (currentValue < redeemValue) return _transfer(address(this), msg.sender, shares);

		// // if vault earned money, subtract earnings since withdrawal request
		uint256 sharesOut = (shares * redeemValue) / currentValue;
		uint256 sharesToBurn = shares - sharesOut;

		_transfer(address(this), msg.sender, sharesOut);
		_burn(address(this), sharesToBurn);
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

	/// @notice enables withdrawal made prior to current timestamp
	/// based specified exchange rate
	function _processWithdraw() internal {
		withdrawTimestamp = block.timestamp;
	}

	/// UTILS
	function redeemIsReady(address user) external view returns (bool) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[user];
		return withdrawTimestamp >= withdrawRecord.timestamp;
	}

	function getWithdrawStatus(address user) external view returns (WithdrawRecord memory) {
		return withdrawLedger[user];
	}

	error Expired();
	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}
