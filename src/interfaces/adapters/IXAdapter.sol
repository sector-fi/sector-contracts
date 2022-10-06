// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

interface IXAdapter {
	function sendMessage(
		uint256 amount,
        address dstVautAddress,
		address srcVaultAddress,
		uint256 destChainId,
		uint16 messageType,
        uint256 srcChainId
	) external;
}
