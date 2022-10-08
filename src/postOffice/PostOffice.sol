// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import "../interfaces/MsgStructs.sol";

abstract contract PostOffice {
	mapping(address => mapping(messageType => Message[])) internal messageBoard;

	function sendMessage(
		uint256 value,
		address receiverVault,
		address senderVault,
		uint256 receiverChainId,
		uint256 senderChainId,
		messageType msgType
	) external virtual;

	// This function will consume all messages from board
	// for a specific type of message
	function readMessage(messageType msgType) external returns (Message[] memory messages) {
		// Read from storage
		Message[] storage storagedMessages = messageBoard[msg.sender][msgType];

		uint256 length = storagedMessages.length;
		messages = new Message[](length);

		for (uint256 i = length; i > 0; ) {
			messages[i - 1] = storagedMessages[i - 1];
			storagedMessages.pop();

			unchecked {
				i++;
			}
		}

		return messages;
	}

	// Returns only total value on board
	// Gas is cheaper here and consumer doesn't need to loop a response
	function readMessageReduce(messageType msgType) external returns (uint256 total) {
		Message[] storage storagedMessages = messageBoard[msg.sender][msgType];
		total = 0;

		for (uint256 i = storagedMessages.length; i > 0; ) {
			total += storagedMessages[i - 1].value;
			storagedMessages.pop();

			unchecked {
				i++;
			}
		}

		return total;
	}

	modifier receiverFirewall(address receiver, address sender, uint16 senderChainId) {
		xChainIntegrator receiver = xChainIntegrator(receiver);

		if (!receiver.checkAddrBook(sender, senderChainId)) revert SenderNotAllowed(sender, senderChainId);
		_;
	}

	error SenderNotAllowed(address sender, uint16 chainId);
}
