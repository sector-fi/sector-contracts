// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract OwnableTransfer is Ownable {
	address public pendingOwner;

	/// @dev Init transfer of ownership of the contract to a new account (`_pendingOwner`).
	/// @param _pendingOwner pending owner of contract
	/// Can only be called by the current owner.
	function transferOwnership(address _pendingOwner) public virtual override onlyOwner {
		pendingOwner = _pendingOwner;
		emit OwnershipTransferInitiated(owner(), _pendingOwner);
	}

	/// @dev Accept transfer of ownership of the contract.
	/// Can only be called by the pendingOwner.
	function acceptOwnership() external {
		address newOwner = pendingOwner;
		if (msg.sender != newOwner) revert OnlyPendingOwner();
		_transferOwnership(newOwner);
	}

	event OwnershipTransferInitiated(address owner, address pendingOwner);

	error OnlyPendingOwner();
}
