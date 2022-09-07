// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { Bank, Pool } from "../../bank/Bank.sol";
import { MockVault } from "../mocks/MockVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract BankTest is SectorTest, ERC1155Holder {
	Bank bank;
	MockVault vault;
	MockERC20 token;
	address guardian = address(1);
	address manager = address(2);
	address treasury = address(3);

	function setUp() public {
		token = new MockERC20("Mock", "Mock", 6);
		bank = new Bank("api.sector.finance/<id>.json", address(this), guardian, manager, treasury);
		vault = new MockVault(bank);
		vault.addPool(address(token));
		bank.addPool(
			Pool({
				id: 0,
				exists: true,
				decimals: token.decimals(),
				managementFee: 1000, // 10%
				vault: address(vault)
			})
		);
		token.approve(address(vault), type(uint256).max);
	}

	function testInit() public {
		assertEq(bank.owner(), address(this));
	}

	function testAddPool() public {
		bank.addPool(
			Pool({
				vault: address(vault),
				id: 1,
				managementFee: 1000, // 10%
				decimals: token.decimals(),
				exists: true
			})
		);
	}

	function testTokenConversion() public {
		address vaultAddr = address(40);
		uint96 vaultId = 99;
		uint256 poolToken = bank.getTokenId(vaultAddr, vaultId);
		(address tokenVault, uint256 tokenPoolId) = bank.getTokenInfo(poolToken);
		assertEq(vaultAddr, tokenVault);
		assertEq(vaultId, tokenPoolId);
	}

	function testDepositWithdraw() public {
		uint256 amount = 10e18;
		token.mint(address(this), amount);
		vault.deposit(0, address(this), amount);

		uint256 tokenId = bank.getTokenId(address(vault), 0);

		assertEq(bank.balanceOf(address(this), tokenId), amount);

		vault.withdraw(0, address(this), amount);

		assertEq(bank.balanceOf(address(this), tokenId), 0);
		assertEq(token.balanceOf(address(this)), amount);
	}

	function testPoolNotFound() public {
		uint256 amount = 10e18;
		token.mint(address(this), amount);
		vault.addPool(address(token));
		vm.expectRevert(Bank.PoolNotFound.selector);
		vault.deposit(1, address(this), amount);
	}
}
