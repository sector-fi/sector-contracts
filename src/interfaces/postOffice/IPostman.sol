// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

interface IPostPostman {
	function deliverMessage(
		uint256 _amount,
		address _dstVautAddress,
		address _srcVautAddress,
		address _dstPostman,
		uint256 _dstChainId,
		uint16 _messageType
	) external;
}