// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;
import "../MsgStructs.sol";

interface IPostOffice {
	function sendMessage(
		address receiverAddr,
		Message calldata message,
		uint16 receiverChainId,
		messageType msgType
	) external;

	function writeMessage(
		address receiver,
		Message calldata message,
		messageType msgType
	) external;

	function readMessage(messageType msgType) external returns (Message[] memory messages);

	function readMessageSumReduce(messageType msgType)
		external
		returns (uint256 acc, uint256 count);
}
