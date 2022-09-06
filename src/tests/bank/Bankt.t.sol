// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { Bank } from "../../bank/Bank.sol";

import "hardhat/console.sol";

contract BankTest is SectorTest {
	Bank bank;
	address guardian = address(1);
	address manager = address(2);
	address treasury = address(3);

	function setUp() public {
		bank = new Bank("api.sector.finance/<id>.json", address(this), guardian, manager, treasury);
	}

	function testTokenConversion() public {
		address vaultAddr = address(40);
		uint96 vaultId = 99;
		uint256 token = bank.getTokenId(vaultAddr, vaultId);
		(address tokenVault, uint256 tokenPoolId) = bank.getTokenInfo(token);
		assertEq(vaultAddr, tokenVault);
		assertEq(vaultId, tokenPoolId);
	}
}
