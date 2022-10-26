// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { CallProxy } from "../interfaces/adapters/IMultichainAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPostman } from "../interfaces/postOffice/IPostman.sol";
import { XChainIntegrator } from "../vaults/sectorVaults/XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

contract MultichainPostman is Ownable, IPostman {
	address public anyCall;
	address public anycallExecutor;
	address public refundTo;

	constructor(address _anyCall, address _refundTo) {
		anyCall = _anyCall;
		anycallExecutor = CallProxy(_anyCall).executor();
		refundTo = _refundTo;
	}

	/*/////////////////////////////////////////////////////
					Messaging Logic
	/////////////////////////////////////////////////////*/

	function deliverMessage(
		Message calldata _msg,
		address _dstVautAddress,
		address _dstPostman,
		MessageType _messageType,
		uint16 _dstChainId
	) external payable {
		if (address(this).balance == 0) revert NoBalance();

		Message memory msgToMultichain = Message({
			value: _msg.value,
			sender: msg.sender,
			client: _msg.client,
			chainId: _msg.chainId
		});

		bytes memory payload = abi.encode(msgToMultichain, _dstVautAddress, _messageType);
		CallProxy(anyCall).anyCall{ value: msg.value }(
			_dstPostman,
			payload,
			address(0),
			_dstChainId,
			2
		);
	}

	function anyExecute(bytes memory _data) external returns (bool success, bytes memory result) {
		(Message memory _msg, address _dstVaultAddress, uint16 _messageType) = abi.decode(
			_data,
			(Message, address, uint16)
		);

		emit MessageReceived(_msg.sender, _msg.value, _dstVaultAddress, _messageType, _msg.chainId);

		XChainIntegrator(_dstVaultAddress).receiveMessage(_msg, MessageType(_messageType));

		success = true;
		result = "";
	}

	/*/////////////////////////////////////////////////////
					UTILS
	/////////////////////////////////////////////////////*/

	function _estimateFee(
		uint16 _dstChainId,
		address _dstVaultAddress,
		MessageType _messageType,
		Message calldata _msg
	) internal view returns (uint256) {
		Message memory msgToMultichain = Message({
			value: _msg.value,
			sender: msg.sender,
			client: _msg.client,
			chainId: _msg.chainId
		});

		bytes memory payload = abi.encode(msgToMultichain, _dstVaultAddress, _messageType);

		uint256 messageFee = CallProxy(anyCall).calcSrcFees("0", _dstChainId, payload.length);

		return messageFee;
	}

	function estimateFee(
		uint16 _dstChainId,
		address _dstVaultAddress,
		MessageType _messageType,
		Message calldata _msg
	) external view returns (uint256) {
		return _estimateFee(_dstChainId, _dstVaultAddress, _messageType, _msg);
	}

	function setRefundTo(address _refundTo) external onlyOwner {
		refundTo = _refundTo;
	}

	function fundPostman() external payable override {}

	receive() external payable {
		(bool sent, ) = refundTo.call{ value: msg.value }("");
		if (!sent) revert RefundFailed();
	}

	/*/////////////////////////////////////////////////////
					EVENTS
	/////////////////////////////////////////////////////*/
	event MessageReceived(
		address srcVaultAddress,
		uint256 amount,
		address dstVaultAddress,
		uint16 messageType,
		uint256 srcChainId
	);

	/*/////////////////////////////////////////////////////
					ERRORS
	/////////////////////////////////////////////////////*/
	error RefundFailed();
	error NoBalance();
}
