// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

interface CallProxy {
	function anyCall(
		address _to,
		bytes calldata _data,
		address _fallback,
		uint256 _toChainID,
		uint256 _flags
	) external;
}