// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "./ERC4626.sol";

struct WithdrawRecord {
	uint256 timestamp;
	uint256 amount;
}

/// TODO withdraw time limit? and cancel after?
/// TODO cancel withdraw?

abstract contract BatchedWithdraw is ERC4626 {
	using SafeERC20 for ERC20;

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	uint256 public withdrawTimestamp;
	uint256 public withdrawSharePrice; // exchage rate 1e18 shares to underlying
	uint256 public pendingWithdrawal;

	mapping(address => WithdrawRecord) public withdrawLedger;

	function requestRedeem(uint256 shares) public {
		return requestRedeem(shares, msg.sender);
	}

	function requestRedeem(uint256 shares, address owner) public {
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
		// TODO should we burn shares right away?
		_transfer(owner, address(this), shares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		withdrawRecord.timestamp = block.timestamp;
		withdrawRecord.amount += shares;
		pendingWithdrawal += shares;
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
		if (withdrawRecord.amount == 0) revert ZeroAmount();
		if (withdrawRecord.timestamp > withdrawTimestamp) revert NotReady();
		amountOut = (withdrawRecord.amount * withdrawSharePrice) / 1e18;
		uint256 burnShares = withdrawRecord.amount;
		pendingWithdrawal -= withdrawRecord.amount;
		withdrawRecord.amount = 0;
		_burn(address(this), burnShares);
		ERC20(asset).transfer(receiver, amountOut);
		emit Withdraw(msg.sender, receiver, owner, amountOut, burnShares);
	}

	/// @notice enables withdrawal made prior to current timestamp
	/// based specified exchange rate
	function _processWithdraw(uint256 _sharesToUnderlying) internal {
		withdrawSharePrice = _sharesToUnderlying;
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

	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}
