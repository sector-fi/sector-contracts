// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { CallProxy } from "../interfaces/adapters/IMultichainAdapter.sol";
import { IPostOffice } from "../interfaces/postOffice/IPostOffice.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/MsgStructs.sol";

contract MultichainPostman is Ownable {
	address public anyCall;
	address public anycallExecutor;

	IPostOffice public immutable postOffice;

	constructor(address _anyCall, address _postOffice) {
		anyCall = _anyCall;
		anycallExecutor = CallProxy(_anyCall).executor();
		postOffice = IPostOffice(_postOffice);
		transferOwnership(_postOffice);
	}

	// owner = postoffice
	function deliverMessage(
		uint256 _amount,
		address _dstVautAddress,
		address _srcVautAddress,
		address _dstPostman,
		uint256 _dstChainId,
		uint16 _messageType
	) external onlyOwner {
		bytes memory payload = abi.encode(_amount, _srcVautAddress, _dstVautAddress, _messageType);
		CallProxy(anyCall).anyCall(_dstPostman, payload, address(0), _dstChainId, 2);
	}

	function anyExecute(bytes memory _data) external returns (bool success, bytes memory result) {
		(address from, uint256 fromChainId, ) = CallProxy(anycallExecutor).context();

		// decode payload sent from source chain
		(
			uint256 _amount,
			address _srcVaultAddress,
			address _dstVaultAddress,
			uint16 _messageType
		) = abi.decode(_data, (uint256, address, address, uint16));

		emit MessageReceived(
			_srcVaultAddress,
			_amount,
			_dstVaultAddress,
			_messageType,
			fromChainId
		);

		// send message to postOffice to be validated and processed
		postOffice.writeMessage(
			_dstVaultAddress,
			Message(_amount, _srcVaultAddress, uint16(fromChainId)),
			_messageType
		);

		success = true;
		result = "";
	}

	/* EVENTS */
	event MessageReceived(
		address srcVaultAddress,
		uint256 amount,
		address dstVaultAddress,
		uint16 messageType,
		uint256 srcChainId
	);
}
