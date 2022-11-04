// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { ERC4626, SectorBase, AggregatorVault, BatchedWithdraw, RedeemParams, DepositParams, IVaultStrategy, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorVault.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { EAction } from "interfaces/Structs.sol";
import { VaultType } from "interfaces/Structs.sol";

import "hardhat/console.sol";

contract AggregatorVaultTest is SectorTest, SCYVaultSetup {
	IVaultStrategy strategy1;
	IVaultStrategy strategy2;
	IVaultStrategy strategy3;

	WETH underlying;

	AggregatorVault vault;
	AggregatorVault s3;

	function setUp() public {
		underlying = new WETH();

		SCYVault s1 = setUpSCYVault(address(underlying));
		SCYVault s2 = setUpSCYVault(address(underlying));
		s3 = new AggregatorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		strategy1 = IVaultStrategy(address(s1));
		strategy2 = IVaultStrategy(address(s2));
		strategy3 = IVaultStrategy(address(s3));

		vault = new AggregatorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		// lock min liquidity
		sectDeposit(vault, owner, mLp);
		scyDeposit(s1, owner, mLp);
		scyDeposit(s2, owner, mLp);
		sectDeposit(s3, owner, mLp);

		vault.addStrategy(strategy1);
		vault.addStrategy(strategy2);
		vault.addStrategy(strategy3);
	}

	receive() external payable {}

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
		skip(1);

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

		uint256 pendingWithdraw = vault.convertToAssets(vault.pendingRedeem());
		uint256 withdrawShares = (pendingWithdraw * strategy1.exchangeRateUnderlying()) / 1e18;

		withdrawFromStrat(strategy1, withdrawShares);

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

		uint256 pendingWithdraw = vault.convertToAssets(vault.pendingRedeem());
		uint256 withdrawShares = (pendingWithdraw * strategy1.exchangeRateUnderlying()) / 1e18;

		withdrawFromStrat(strategy1, withdrawShares);
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

		uint256 s3Balance = s3.balanceOf(address(vault));
		requestRedeemFromStrat(strategy3, s3Balance / 2);
		skip(1);
		sectHarvest(s3);
		skip(1);

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
		uint256 pendingWithdraw = vault.convertToAssets(vault.pendingRedeem());
		assertEq(pendingWithdraw, amnt / 2, "pending withdraw");
		sectHarvest(vault);
		assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float amnt half");

		DepositParams[] memory dParams = new DepositParams[](1);
		dParams[0] = (DepositParams(strategy1, VaultType.Strategy, amnt / 2, 0));
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
		vm.expectRevert(SectorBase.RecentHarvest.selector);
		vault.emergencyRedeem();

		skip(vault.maxHarvestInterval());
		vault.emergencyRedeem();

		assertApproxEqAbs(underlying.balanceOf(user1), 100e18, mLp, "recovered float");

		uint256 b1 = IERC20(address(strategy1)).balanceOf(user1);
		uint256 b2 = IERC20(address(strategy2)).balanceOf(user1);
		uint256 b3 = IERC20(address(strategy3)).balanceOf(user1);

		strategy1.redeem(user1, b1, address(underlying), 0);
		strategy2.redeem(user1, b2, address(underlying), 0);

		s3.requestRedeem(b3, user1);

		vm.stopPrank();

		skip(1);
		sectHarvest(s3);

		vm.prank(user1);
		strategy3.redeem();

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

		EAction[] memory actions = new EAction[](1);
		actions[0] = EAction(address(underlying), 0, callData);

		vault.emergencyAction(actions);
		assertEq(underlying.balanceOf(user2), amnt / 2);
		assertEq(underlying.balanceOf(address(vault)), amnt / 2);
	}

	function testDepositRedeemNative() public {
		vault = new AggregatorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			true,
			3 days,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);
		sectDeposit(vault, owner, mLp);

		uint256 amnt = 1000e18;
		deal(self, amnt);
		vault.deposit{ value: amnt }(amnt, self);

		assertEq(vault.underlyingBalance(self), amnt);
		assertEq(self.balance, 0);

		uint256 shares = vault.balanceOf(self);
		vault.requestRedeem(shares, self);
		skip(1);
		sectHarvest(vault);
		vault.redeemNative();

		assertEq(self.balance, amnt);
	}

	function testPendingRedeemLoss() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt);

		depositToStrat(strategy1, amnt);
		sectInitRedeem(vault, user1, 1e18);

		MockERC20(underlying).burn(address(strategy1.strategy()), amnt / 10);

		uint256 shares = IERC20(address(strategy1)).balanceOf(address(vault));
		withdrawFromStrat(strategy1, shares);

		sectHarvest(vault);

		sectHarvest(vault);
		sectCompleteRedeem(vault, user1);
		assertApproxEqAbs(underlying.balanceOf(user1), amnt - amnt / 10, mLp);
	}

	function testMaxTvl() public {
		vault.setMaxTvl(1e6);
		sectDeposit(vault, user1, 1e6 - mLp);

		assertEq(vault.maxDeposit(user1), 0);

		vm.startPrank(user1);
		underlying.approve(address(vault), 1);
		underlying.mint(user1, 1);
		vm.expectRevert(ERC4626.OverMaxTvl.selector);
		vault.deposit(1, user1);
		vm.stopPrank();
	}

	/// UTILS

	function depositToStrat(IVaultStrategy strategy, uint256 amount) public {
		DepositParams[] memory params = new DepositParams[](1);
		params[0] = (DepositParams(strategy, strategy.vaultType(), amount, 0));
		vault.depositIntoStrategies(params);
	}

	function withdrawFromStrat(IVaultStrategy strategy, uint256 amount) public {
		RedeemParams[] memory rParams = new RedeemParams[](1);
		rParams[0] = (RedeemParams(strategy, strategy.vaultType(), amount, 0));
		vault.withdrawFromStrategies(rParams);
	}

	function requestRedeemFromStrat(IVaultStrategy strategy, uint256 amount) public {
		RedeemParams[] memory rParams = new RedeemParams[](1);
		rParams[0] = (RedeemParams(strategy, strategy.vaultType(), amount, 0));
		vault.requestRedeemFromStrategies(rParams);
	}

	function sectHarvest(AggregatorVault _vault) public {
		vm.startPrank(manager);
		uint256 expectedTvl = _vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectHarvestRevert(AggregatorVault _vault, bytes4 err) public {
		vm.startPrank(manager);
		uint256 expectedTvl = vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		vm.expectRevert(err);
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectDeposit(
		AggregatorVault _vault,
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
		AggregatorVault _vault,
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

	function sectCompleteRedeem(AggregatorVault _vault, address acc) public {
		vm.startPrank(acc);
		_vault.redeem();
		vm.stopPrank();
	}

	function sectDeposit3Strats(
		AggregatorVault _vault,
		uint256 a1,
		uint256 a2,
		uint256 a3
	) public {
		DepositParams[] memory dParams = new DepositParams[](3);
		dParams[0] = (DepositParams(strategy1, strategy1.vaultType(), a1, 0));
		dParams[1] = (DepositParams(strategy2, strategy2.vaultType(), a2, 0));
		dParams[2] = (DepositParams(strategy3, strategy3.vaultType(), a3, 0));
		_vault.depositIntoStrategies(dParams);
	}

	function sectRedeem3Strats(
		AggregatorVault _vault,
		uint256 a1,
		uint256 a2,
		uint256 a3
	) public {
		RedeemParams[] memory rParams = new RedeemParams[](3);
		rParams[0] = (RedeemParams(strategy1, strategy1.vaultType(), a1, 0));
		rParams[1] = (RedeemParams(strategy2, strategy2.vaultType(), a2, 0));
		rParams[2] = (RedeemParams(strategy3, strategy3.vaultType(), a3, 0));
		_vault.withdrawFromStrategies(rParams);
	}
}
