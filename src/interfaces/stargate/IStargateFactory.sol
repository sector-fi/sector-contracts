// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

interface IStargateFactory {
	function getPool(uint256 _pid) external view returns (address);
}
