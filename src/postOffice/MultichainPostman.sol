// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { CallProxy } from "../interfaces/adapters/IMultichainAdapter.sol";
import { IPostOffice } from "../interfaces/postOffice/IPostOffice.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPostman } from "../interfaces/postOffice/IPostman.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";

import "hardhat/console.sol";

contract MultichainPostman is Ownable, IPostman {
	address public anyCall;
	address public anycallExecutor;


	constructor(address _anyCall) {
		anyCall = _anyCall;
		anycallExecutor = CallProxy(_anyCall).executor();
	}

	function deliverMessage(
		Message calldata _msg,
		address _dstVautAddress,
		address _dstPostman,
		messageType _messageType,
		uint16 _dstChainId
	) external onlyOwner {
		bytes memory payload = abi.encode(_msg, _dstVautAddress, _messageType);
		CallProxy(anyCall).anyCall(_dstPostman, payload, address(0), _dstChainId, 2);
	}

	function anyExecute(bytes memory _data) external returns (bool success, bytes memory result) {
		// decode payload sent from source chain
		(Message memory _msg, address _dstVaultAddress, uint16 _messageType) = abi.decode(
			_data,
			(Message, address, uint16)
		);

		emit MessageReceived(_msg.sender, _msg.value, _dstVaultAddress, _messageType, _msg.chainId);

		// Send message to dst vault
		XChainIntegrator(_dstVaultAddress).receiveMessage(_msg, messageType(_messageType));

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
