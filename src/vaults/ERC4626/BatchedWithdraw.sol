// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626, IWETH } from "./ERC4626.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";

// import "hardhat/console.sol";

struct WithdrawRecord {
	uint256 timestamp;
	uint256 shares;
	uint256 value; // this the current value (also max withdraw value)
}

abstract contract BatchedWithdraw is ERC4626 {
	using SafeERC20 for ERC20;

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	uint256 public lastHarvestTimestamp;
	uint256 public pendingRedeem;

	mapping(address => WithdrawRecord) public withdrawLedger;

	constructor() {
		lastHarvestTimestamp = block.timestamp;
	}

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
		pendingRedeem += shares;
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

	/// @dev safest UI method
	function redeemNative() public virtual returns (uint256 amountOut) {
		return redeemNative(msg.sender);
	}

	function redeemNative(address receiver) public virtual returns (uint256 amountOut) {
		if (!useNativeAsset) revert NotNativeAsset();
		uint256 shares;
		(amountOut, shares) = _redeem(msg.sender);

		emit Withdraw(msg.sender, receiver, msg.sender, amountOut, shares);

		IWETH(address(asset)).withdraw(amountOut);
		SafeETH.safeTransferETH(receiver, amountOut);
	}

	function redeem(address receiver) public virtual returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(msg.sender);
		emit Withdraw(msg.sender, receiver, msg.sender, amountOut, shares);
		asset.safeTransfer(receiver, amountOut);
	}

	/// @dev should only be called by manager on behalf of xVaults
	function _xRedeem(address xVault, address _vault) internal virtual returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(xVault);
		emit Withdraw(_vault, _vault, _vault, amountOut, shares);
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
		beforeWithdraw(amountOut, shares);
		withdrawRecord.value = 0;
		withdrawRecord.shares = 0;
		_burn(address(this), shares);
	}

	/// helper method to get xChain bridge amount
	// function pendingRedeem(address account) public view returns (uint256 amountOut) {
	// 	WithdrawRecord storage withdrawRecord = withdrawLedger[account];

	// 	if (withdrawRecord.value == 0) revert ZeroAmount();
	// 	if (withdrawRecord.timestamp >= lastHarvestTimestamp) revert NotReady();

	// 	// value of shares at time of redemption request
	// 	return _getWithdrawAmount(withdrawRecord.shares, withdrawRecord.value);
	// }

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

		uint256 shares = withdrawRecord.shares;
		// value of shares at time of redemption request
		uint256 redeemValue = withdrawRecord.value;
		uint256 currentValue = convertToAssets(shares);

		// update accounting
		withdrawRecord.value = 0;
		// pendingWithdraw -= redeemValue;
		pendingRedeem -= shares;

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

	/// UTILS
	function redeemIsReady(address user) external view returns (bool) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[user];
		return lastHarvestTimestamp > withdrawRecord.timestamp && withdrawRecord.value > 0;
	}

	function getWithdrawStatus(address user) external view returns (WithdrawRecord memory) {
		return withdrawLedger[user];
	}

	error NotNativeAsset();
	error Expired();
	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}
