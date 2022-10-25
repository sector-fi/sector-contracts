// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;
import "../MsgStructs.sol";

interface IPostman {
	function deliverMessage(
		Message calldata _msg,
		address _dstVautAddress,
		address _dstPostman,
		MessageType _messageType,
		uint16 _dstChainId
	) external payable;

	function estimateFee(
		uint16 _dstChainId,
		address _dstVaultAddress,
		MessageType _messageType,
		Message calldata _msg
	) external view returns (uint256);

	function setRefundTo(address _refundTo) external;
}
