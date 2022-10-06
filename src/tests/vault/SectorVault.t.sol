// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
// import { ISCYStrategy } from "../../interfaces/scy/ISCYStrategy.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorVault, BatchedWithdraw } from "../../vaults/SectorVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract SectorVaultTest is SectorTest, SCYVaultSetup {
	SCYVault strategy1;
	SCYVault strategy2;
	SCYVault strategy3;

	WETH underlying;

	SectorVault vault;

	function setUp() public {
		underlying = new WETH();

		strategy1 = setUpSCYVault(address(underlying));
		strategy2 = setUpSCYVault(address(underlying));
		strategy3 = setUpSCYVault(address(underlying));

		vault = new SectorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			owner,
			guardian,
			manager,
			treasury,
			DEFAULT_PERFORMANCE_FEE
		);

		// lock min liquidity
		sectDeposit(vault, owner, vault.MIN_LIQUIDITY());
		scyDeposit(strategy1, owner, strategy1.MIN_LIQUIDITY());
		scyDeposit(strategy2, owner, strategy2.MIN_LIQUIDITY());
		scyDeposit(strategy3, owner, strategy3.MIN_LIQUIDITY());
	}

	function testDeposit() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);
		assertEq(vault.balanceOfUnderlying(user1), amnt);
	}

	function testWithdraw() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);
		uint256 shares = vault.balanceOf(user1);
		sectInitRedeem(vault, user1, 1e18 / 2);

		assertEq(vault.balanceOf(user1), shares / 2);

		assertFalse(vault.redeemIsReady(user1), "redeem not ready");

		vm.expectRevert(BatchedWithdraw.NotReady.selector);
		vm.prank(user1);
		vault.redeem();

		sectHarvest(vault);

		assertTrue(vault.redeemIsReady(user1), "redeem ready");
		sectCompleteRedeem(vault, user1);
		assertEq(vault.balanceOfUnderlying(user1), 100e18 / 2);

		// amount should reset
		vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
		vm.prank(user1);
		vault.redeem();
	}

	function sectHarvest(SectorVault _vault) public {
		vm.startPrank(manager);
		uint256 expectedTvl = vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectDeposit(
		SectorVault _vault,
		address acc,
		uint256 amnt
	) public {
		MockERC20 _underlying = MockERC20(address(_vault.underlying()));
		vm.startPrank(acc);
		_underlying.approve(address(_vault), amnt);
		_underlying.mint(acc, amnt);
		_vault.deposit(amnt, acc);
		vm.stopPrank();
	}

	function sectInitRedeem(
		SectorVault _vault,
		address acc,
		uint256 fraction
	) public {
		vm.startPrank(acc);
		uint256 sharesToWithdraw = (_vault.balanceOf(acc) * fraction) / 1e18;
		_vault.requestRedeem(sharesToWithdraw);
		vm.stopPrank();
	}

	function sectCompleteRedeem(SectorVault _vault, address acc) public {
		vm.startPrank(acc);
		_vault.redeem();
		vm.stopPrank();
	}
}
