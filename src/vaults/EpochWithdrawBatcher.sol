// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeETH } from "../libraries/SafeETH.sol";
import { Accounting } from "../common/Accounting.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// import "hardhat/console.sol";

struct WithdrawRecord {
	uint256 epoch;
	uint256 shares;
}

contract EpochWithdrawBatcher is Ownable {
	using SafeERC20 for IERC20;

	IERC20 public immutable underlying;

	uint256 public epoch;
	uint256 public pendingRedeem;
	uint256 public requestedRedeem;

	mapping(address => WithdrawRecord) public withdrawLedger;
	mapping(uint256 => uint256) public epochExchangeRate;

	// should be created by the vault contract
	constructor(address underlying_) {
		underlying = IERC20(underlying_);
		IERC20(owner()).safeApprove(owner(), type(uint256).max);
		underlying.safeApprove(owner(), type(uint256).max);
	}

	/// @dev redeem request records the value of the redeemed shares at the time of request
	/// at the time of claim, user is able to withdraw the minimum of the
	/// current value and value at time of request
	/// this is to prevent users from pre-emptively submitting redeem claims
	/// and claiming any rewards after the request has been made
	function requestRedeem(
		uint256 shares,
		address owner,
		address redeemer
	) public onlyOwner {
		// do transfer via vault contract

		// yieldToken.safeTransfer(owner, address(this), shares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[redeemer];
		if (withdrawRecord.shares != 0) revert RedeemRequestExists();

		withdrawRecord.epoch = epoch;
		withdrawRecord.shares = shares;
		// track requested shares
		requestedRedeem += shares;
		emit RequestWithdraw(msg.sender, owner, shares);
	}

	function redeem(address account)
		internal
		onlyOwner
		returns (uint256 amountOut, uint256 shares)
	{
		WithdrawRecord storage withdrawRecord = withdrawLedger[account];

		if (withdrawRecord.shares == 0) revert ZeroAmount();
		/// withdrawRecord.epoch can never be greater than current epoch
		if (withdrawRecord.epoch == epoch) revert NotReady();

		shares = withdrawRecord.shares;

		// actual amount out is the smaller of currentValue and redeemValue
		amountOut = (shares * epochExchangeRate[withdrawRecord.epoch]) / 1e18;

		// update total pending redeem
		pendingRedeem -= shares;

		// important pendingRedeem should update prior to beforeWithdraw call
		withdrawRecord.shares = 0;

		underlying.safeTransfer(account, amountOut);
		/// vault burns token
	}

	/// @notice this methods updates lastEpochTimestamp and alows all pending withdrawals to be completed
	/// @dev ensure that we we have enought funds to process withdrawals
	/// before calling this method
	function processRedeem() public onlyOwner {
		// store current epoch exchange rate
		epochExchangeRate[epoch] = convertToAssets(1e18);
		pendingRedeem = requestedRedeem;
		requestedRedeem = 0;
		// advance epoch
		++epoch;
	}

	function cancelRedeem() public virtual {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];

		/// TODO should we allow cancel after redeem has been processed?
		if (withdrawRecord.epoch < epoch) revert CannotCancelProccesedRedeem();

		uint256 shares = withdrawRecord.shares;

		// update accounting
		withdrawRecord.shares = 0;
		pendingRedeem -= shares;

		// send shares back to user
		IERC20(owner()).safeTransfer(msg.sender, shares);
	}

	function convertToAssets(uint256 shares) public view virtual returns (uint256) {
		uint256 supply = IERC20(owner()).balanceOf(address(this)); // Saves an extra SLOAD if totalSupply is non-zero.
		uint256 assets = underlying.balanceOf(address(this));
		return supply == 0 ? shares : (shares * assets) / supply;
	}

	/// UTILS
	function redeemIsReady(address user) external view returns (bool) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[user];
		return epoch > withdrawRecord.epoch && withdrawRecord.shares > 0;
	}

	function getWithdrawStatus(address user) external view returns (WithdrawRecord memory) {
		return withdrawLedger[user];
	}

	event RequestWithdraw(address indexed caller, address indexed owner, uint256 shares);

	error RedeemRequestExists();
	error CannotCancelProccesedRedeem();
	error NotNativeAsset();
	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}
