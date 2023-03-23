// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYWEpochVaultCommon, SCYWEpochVault } from "./SCYWEpochVaultCommon.sol";

import "hardhat/console.sol";

contract SCYWEpochVaultTest is SCYWEpochVaultCommon {
	function setUp() public {
		setUpCommonTest();
	}

	function setupVault(address _underlying, bool _isNative)
		public
		override
		returns (SCYWEpochVault)
	{
		return setUpSCYVault(_underlying, _isNative);
	}
}
