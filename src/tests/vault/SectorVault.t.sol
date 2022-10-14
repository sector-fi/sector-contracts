// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorBase, SectorVault, BatchedWithdraw, RedeemParams, DepositParams, ISCYStrategy, AuthConfig, FeeConfig } from "../../vaults/SectorVault.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";

import "hardhat/console.sol";

contract SectorVaultTest is SectorTest, SCYVaultSetup {
	ISCYStrategy strategy1;
	ISCYStrategy strategy2;
	ISCYStrategy strategy3;

	WETH underlying;

	SectorVault vault;

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
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			address(69) // temporary
		);

		// lock min liquidity
		sectDeposit(vault, owner, mLp);
		scyDeposit(s1, owner, mLp);
		scyDeposit(s2, owner, mLp);
		scyDeposit(s3, owner, mLp);

		vault.addStrategy(strategy1);
		vault.addStrategy(strategy2);
		vault.addStrategy(strategy3);
	}

	function testAddRemoveStrat() public {
		vault.removeStrategy(strategy2);
		assertEq(address(vault.strategyIndex(1)), address(strategy3));
		assertEq(vault.totalStrategies(), 2);

		vm.expectRevert(SectorBase.StrategyNotFound.selector);
		vault.removeStrategy(strategy2);

		vault.addStrategy(strategy2);
		assertEq(address(vault.strategyIndex(2)), address(strategy2));
		assertEq(vault.totalStrategies(), 3);

		vm.expectRevert(SectorBase.StrategyExists.selector);
		vault.addStrategy(strategy2);
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
		sectInitRedeem(vault, user1, 1e18 / 4);

		assertEq(vault.balanceOf(user1), (shares * 3) / 4, "3/4 of shares remains");

		assertFalse(vault.redeemIsReady(user1), "redeem not ready");

		vm.expectRevert(BatchedWithdraw.NotReady.selector);
		vm.prank(user1);
		vault.redeem();

		sectHarvest(vault);

		assertTrue(vault.redeemIsReady(user1), "redeem ready");
		sectCompleteRedeem(vault, user1);
		assertEq(vault.underlyingBalance(user1), (100e18 * 3) / 4, "3/4 of deposit remains");

		assertEq(underlying.balanceOf(user1), amnt / 4);

		// amount should reset
		vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
		vm.prank(user1);
		vault.redeem();
	}

	function testWithdrawAfterProfit() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);

		// funds deposited
		depositToStrat(strategy1, amnt);
		underlying.mint(address(strategy1), 10e18); // 10% profit

		sectInitRedeem(vault, user1, 1e18 / 4);

		sectHarvestRevert(vault, SectorBase.NotEnoughtFloat.selector);

		withdrawFromStrat(strategy1, amnt / 4);

		sectHarvest(vault);

		vm.prank(user1);
		assertApproxEqAbs(vault.getPenalty(), .09e18, mLp);

		sectCompleteRedeem(vault, user1);

		assertEq(underlying.balanceOf(user1), amnt / 4);
	}

	function testWithdrawAfterLoss() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);

		// funds deposited
		depositToStrat(strategy1, amnt);
		underlying.burn(address(strategy1.strategy()), 10e18); // 10% loss

		sectInitRedeem(vault, user1, 1e18 / 4);

		uint256 shares = strategy1.underlyingToShares(amnt / 4);
		withdrawFromStrat(strategy1, shares);

		sectHarvest(vault);

		vm.prank(user1);
		assertEq(vault.getPenalty(), 0);

		sectCompleteRedeem(vault, user1);

		assertApproxEqAbs(underlying.balanceOf(user1), (amnt * .9e18) / 4e18, mLp);
	}

	function testCancelWithdraw() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt / 4);
		sectDeposit(vault, user2, (amnt * 3) / 4);

		// funds deposited
		depositToStrat(strategy1, amnt);
		underlying.mint(address(strategy1), 10e18 + (mLp) / 10); // 10% profit

		sectInitRedeem(vault, user1, 1e18);
		sectHarvestRevert(vault, SectorBase.NotEnoughtFloat.selector);

		withdrawFromStrat(strategy1, amnt / 4);
		sectHarvest(vault);

		vm.prank(user1);
		vault.cancelRedeem();

		uint256 profit = ((10e18 + (mLp) / 10) * 9) / 10;
		uint256 profitFromBurn = (profit / 4) / 4;
		assertApproxEqAbs(vault.underlyingBalance(user1), amnt / 4 + profitFromBurn, .1e18);
		assertEq(underlying.balanceOf(user1), 0);

		// amount should reset
		vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
		vm.prank(user1);
		vault.redeem();
	}

	function testDepositWithdrawStrats() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt - mLp);

		sectDeposit3Strats(vault, 200e18, 300e18, 500e18);

		assertEq(vault.getTvl(), amnt);
		assertEq(vault.totalChildHoldings(), amnt);

		sectRedeem3Strats(vault, 200e18 / 2, 300e18 / 2, 500e18 / 2);

		assertEq(vault.getTvl(), amnt);
		assertEq(vault.totalChildHoldings(), amnt / 2);
	}

	function testFloatAccounting() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);

		assertEq(vault.floatAmnt(), amnt + mLp);

		depositToStrat(strategy1, amnt);

		assertEq(vault.floatAmnt(), mLp);

		sectInitRedeem(vault, user1, 1e18 / 2);

		withdrawFromStrat(strategy1, amnt / 2);

		assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float");
		assertEq(vault.pendingWithdraw(), amnt / 2, "pending withdraw");
		sectHarvest(vault);
		assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float amnt half");

		DepositParams[] memory dParams = new DepositParams[](1);
		dParams[0] = (DepositParams(strategy1, amnt / 2, 0));
		vm.expectRevert(SectorBase.NotEnoughtFloat.selector);
		vault.depositIntoStrategies(dParams);

		vm.prank(user1);
		vault.redeem();
		assertEq(vault.floatAmnt(), mLp);
	}

	function testPerformanceFee() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);

		depositToStrat(strategy1, amnt);
		underlying.mint(address(strategy1), 10e18 + (mLp) / 10); // 10% profit

		uint256 expectedTvl = vault.getTvl();
		assertEq(expectedTvl, 110e18 + mLp);

		sectHarvest(vault);

		assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
		assertApproxEqAbs(vault.underlyingBalance(user1), 109e18, mLp);
	}

	function testManagementFee() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);
		vault.setManagementFee(.01e18);

		depositToStrat(strategy1, amnt);

		skip(365 days);
		sectHarvest(vault);

		assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
		assertApproxEqAbs(vault.underlyingBalance(user1), 99e18, mLp);
	}

	function testEmergencyRedeem() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt);
		sectDeposit3Strats(vault, 200e18, 300e18, 400e18);
		skip(1);

		vm.startPrank(user1);

		vault.emergencyRedeem();

		assertApproxEqAbs(underlying.balanceOf(user1), 100e18, mLp, "recovered float");

		uint256 b1 = IERC20(address(strategy1)).balanceOf(user1);
		uint256 b2 = IERC20(address(strategy2)).balanceOf(user1);
		uint256 b3 = IERC20(address(strategy3)).balanceOf(user1);

		strategy1.redeem(user1, b1, address(underlying), 0);
		strategy2.redeem(user1, b2, address(underlying), 0);
		strategy3.redeem(user1, b3, address(underlying), 0);

		assertApproxEqAbs(underlying.balanceOf(user1), amnt, 1, "recovered amnt");
		assertApproxEqAbs(vault.getTvl(), mLp, 1);
	}

	function testEmergencyAction() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt - mLp);

		bytes memory callData = abi.encodeWithSignature(
			"transfer(address,uint256)",
			user2,
			amnt / 2
		);
		vault.emergencyAction(address(underlying), callData);
		assertEq(underlying.balanceOf(user2), amnt / 2);
		assertEq(underlying.balanceOf(address(vault)), amnt / 2);
	}

	/// UTILS

	function depositToStrat(ISCYStrategy strategy, uint256 amount) public {
		DepositParams[] memory params = new DepositParams[](1);
		params[0] = (DepositParams(strategy, amount, 0));
		vault.depositIntoStrategies(params);
	}

	function withdrawFromStrat(ISCYStrategy strategy, uint256 amount) public {
		RedeemParams[] memory rParams = new RedeemParams[](1);
		rParams[0] = (RedeemParams(strategy, amount, 0));
		vault.withdrawFromStrategies(rParams);
	}

	function sectHarvest(SectorVault _vault) public {
		vm.startPrank(manager);
		uint256 expectedTvl = vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectHarvestRevert(SectorVault _vault, bytes4 err) public {
		vm.startPrank(manager);
		uint256 expectedTvl = vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		vm.expectRevert(err);
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
		// advance 1s
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
		// advance 1s to ensure we don't have =
		skip(1);
	}

	function sectCompleteRedeem(SectorVault _vault, address acc) public {
		vm.startPrank(acc);
		_vault.redeem();
		vm.stopPrank();
	}

	function sectDeposit3Strats(
		SectorVault _vault,
		uint256 a1,
		uint256 a2,
		uint256 a3
	) public {
		DepositParams[] memory dParams = new DepositParams[](3);
		dParams[0] = (DepositParams(strategy1, a1, 0));
		dParams[1] = (DepositParams(strategy2, a2, 0));
		dParams[2] = (DepositParams(strategy3, a3, 0));
		_vault.depositIntoStrategies(dParams);
	}

	function sectRedeem3Strats(
		SectorVault _vault,
		uint256 a1,
		uint256 a2,
		uint256 a3
	) public {
		RedeemParams[] memory rParams = new RedeemParams[](3);
		rParams[0] = (RedeemParams(strategy1, a1, 0));
		rParams[1] = (RedeemParams(strategy2, a2, 0));
		rParams[2] = (RedeemParams(strategy3, a3, 0));
		_vault.withdrawFromStrategies(rParams);
	}
}
