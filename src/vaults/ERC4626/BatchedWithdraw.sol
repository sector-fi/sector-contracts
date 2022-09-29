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

	event RequestWithdraw(address indexed user, uint256 shares);

	uint256 public withdrawTimestamp;
	uint256 public sharesToUnderlying;
	uint256 public pendingWithdrawal;

	mapping(address => WithdrawRecord) public withdrawLedger;

	function requestRedeem(uint256 vaultShares) public {
		_transfer(msg.sender, address(this), vaultShares);
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		withdrawRecord.timestamp = block.timestamp;
		withdrawRecord.amount += vaultShares;
		pendingWithdrawal += vaultShares;
		emit RequestWithdraw(msg.sender, vaultShares);
	}

	function withdraw(
		uint256,
		address,
		address
	) public pure override returns (uint256) {
		revert NotImplemented();
	}

	function redeem(
		uint256,
		address receiver,
		address
	) public override returns (uint256 amountOut) {
		WithdrawRecord storage withdrawRecord = withdrawLedger[msg.sender];
		if (withdrawRecord.amount == 0) revert ZeroAmount();
		if (withdrawRecord.timestamp < withdrawTimestamp) revert NotReady();
		amountOut = (withdrawRecord.amount * sharesToUnderlying) / 1e18;
		_burn(address(this), withdrawRecord.amount);
		pendingWithdrawal -= withdrawRecord.amount;
		withdrawRecord.amount = 0;
		ERC20(asset).transfer(receiver, amountOut);
	}

	/// @notice enables withdrawal made prior to current timestamp
	/// based specified exchange rate
	function _processWithdraw(uint256 _sharesToUnderlying) internal {
		sharesToUnderlying = _sharesToUnderlying;
		withdrawTimestamp = block.timestamp;
	}

	error NotImplemented();
	error NotReady();
	error ZeroAmount();
}
