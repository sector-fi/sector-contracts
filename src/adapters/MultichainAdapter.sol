// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

// import { IXAdapter } from "../interfaces/adapters/IXAdapter.sol";
import { CallProxy } from "../interfaces/adapters/IMultichainAdapter.sol";
import { XAdapter } from "./XAdapter.sol";

contract MultichainAdapter is XAdapter {
	address public anyCall;
	mapping(uint256 => address) public adapters;

	struct message {
		uint256 deposits;
		uint256 withdrawals;
		uint256 redeemed;
	}

	constructor(address _anyCall) {
		anyCall = _anyCall;
	}

	function sendMessage(
		uint256 _amount,
		address _dstVautAddress,
		address _srcVautAddress,
		uint256 _dstChainId,
		uint16 _messageType,
		uint256 _srcChainId
	) external override onlyOwner {
		bytes memory payload = abi.encode(
			_amount,
			_srcVautAddress,
			_dstVautAddress,
			_messageType,
			_srcChainId
		);
		CallProxy(anyCall).anyCall(adapters[_dstChainId], payload, address(0), _dstChainId, 2);
	}

	// Same here, we need a way to vault call this function
	function setAdapter(uint256 _chainId, address _adapter) external onlyOwner {
		adapters[_chainId] = _adapter;
	}

	function anyExecute(bytes memory _data) external returns (bool success, bytes memory result) {
		// decode payload sent from source chain
		(
			uint256 _amount,
			address _srcVaultAddress,
			address _dstVaultAddress,
			uint16 messageType,
			uint256 _srcChainId
		) = abi.decode(_data, (uint256, address, address, uint16, uint256));

		emit MessageReceived(_srcVaultAddress, _amount, _dstVaultAddress, messageType, _srcChainId);

		success = true;
		result = "";
	}

	/* EVENTS */
	event MessageReceived(
		address destAddress,
		uint256 amount,
		address srcAddress,
		uint16 messageType,
		uint256 srcChainId
	);
}
