// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
// import { ISCYStrategy } from "../../interfaces/scy/ISCYStrategy.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorVault, BatchedWithdraw, RedeemParams, DepositParams, ISCYStrategy } from "../../vaults/SectorVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract SectorVaultTest is SectorTest, SCYVaultSetup {
	ISCYStrategy strategy1;
	ISCYStrategy strategy2;
	ISCYStrategy strategy3;

	WETH underlying;

	SectorVault vault;

	DepositParams[] depParams;
	RedeemParams[] redParams;

	function setUp() public {
		underlying = new WETH();

		SCYVault s1 = setUpSCYVault(address(underlying));
		SCYVault s2 = setUpSCYVault(address(underlying));
		SCYVault s3 = setUpSCYVault(address(underlying));

		strategy1 = ISCYStrategy(address(s1));
		strategy2 = ISCYStrategy(address(s2));
		strategy3 = ISCYStrategy(address(s3));

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
		sectDeposit(vault, owner, mLp);
		scyDeposit(s1, owner, mLp);
		scyDeposit(s2, owner, mLp);
		scyDeposit(s3, owner, mLp);

		depParams.push(DepositParams(strategy1, 0, 0));
		depParams.push(DepositParams(strategy2, 0, 0));
		depParams.push(DepositParams(strategy3, 0, 0));

		redParams.push(RedeemParams(strategy1, 0, 0));
		redParams.push(RedeemParams(strategy2, 0, 0));
		redParams.push(RedeemParams(strategy3, 0, 0));

		vault.addStrategy(strategy1);
		vault.addStrategy(strategy2);
		vault.addStrategy(strategy3);
	}

	function testDeposit() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);
		assertEq(vault.underlyingBalance(user1), amnt);
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
		assertEq(vault.underlyingBalance(user1), 100e18 / 2, "half of deposit");

		// amount should reset
		vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
		vm.prank(user1);
		vault.redeem();
	}

	function testDepositWithdrawStrats() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt - mLp);

		depParams[0].amountIn = 200e18;
		depParams[1].amountIn = 300e18;
		depParams[2].amountIn = 500e18;

		vault.depositIntoStrategies(depParams);

		assertEq(vault.getTvl(), amnt);
		assertEq(vault.totalStrategyHoldings(), amnt);

		redParams[0].shares = depParams[0].amountIn / 2;
		redParams[1].shares = depParams[1].amountIn / 2;
		redParams[2].shares = depParams[2].amountIn / 2;

		vault.withdrawFromStrategies(redParams);

		assertEq(vault.getTvl(), amnt);
		assertEq(vault.totalStrategyHoldings(), amnt / 2);
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
