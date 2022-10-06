// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

abstract contract XAdapter {
	struct Message {
		uint256 value;
		uint256 timestamp;
	}

	mapping(uint16 => mapping(address => Message)) internal messageBoard;

	function sendMessage(
		uint256 amount,
        address dstVautAddress,
		address srcVaultAddress,
		uint256 destChainId,
		uint16 messageType,
        uint256 srcChainId
	) external virtual;

	function readMessage(
        address senderVaultAddress,
		uint16 senderChainId,
		uint256 timestamp
	) external view returns (uint256) {
		Message memory message = messageBoard[senderChainId][senderVaultAddress];

		if (message.timestamp < timestamp) revert MessageExpired();

		return (message.value);
	}

	error MessageExpired();
}
