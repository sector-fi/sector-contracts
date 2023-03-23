// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYVaultCommon, SCYVault } from "./SCYVaultCommon.sol";

import "hardhat/console.sol";

contract SCYVaultTest is SCYVaultCommon {
	function setUp() public {
		setUpCommonTest();
	}

	function setupVault(address _underlying, bool _isNative) public override returns (SCYVault) {
		return setUpSCYVault(_underlying, _isNative);
	}
}
