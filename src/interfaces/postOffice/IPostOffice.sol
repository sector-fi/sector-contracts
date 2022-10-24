// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;
import "../MsgStructs.sol";

interface IPostOffice {
	function sendMessage(
		address receiverAddr,
		Message calldata message,
		uint16 receiverChainId,
		MessageType msgType
	) external;

	function writeMessage(
		address receiver,
		Message calldata message,
		MessageType msgType
	) external;

	function readMessage(MessageType msgType) external returns (Message[] memory messages);

	function readMessageSumReduce(MessageType msgType)
		external
		returns (uint256 acc, uint256 count);
}
