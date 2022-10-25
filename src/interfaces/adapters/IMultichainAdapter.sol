// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

interface CallProxy {
	function anyCall(
		address _to,
		bytes calldata _data,
		address _fallback,
		uint256 _toChainID,
		uint256 _flags
	) external payable;

	function context()
		external
		view
		returns (
			address from,
			uint256 fromChainID,
			uint256 nonce
		);

	function executor() external view returns (address executor);

	function calcSrcFees(
		string calldata _appID,
		uint256 _toChainID,
		uint256 _dataLength
	) external view returns (uint256);
}
