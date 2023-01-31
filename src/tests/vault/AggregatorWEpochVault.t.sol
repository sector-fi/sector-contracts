// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYWEpochVault } from "vaults/ERC5115/SCYWEpochVault.sol";
import { SCYWEpochVaultUtils } from "./SCYWEpochVaultUtils.sol";
import { WETH } from "../mocks/WETH.sol";
import { ERC4626, SectorBaseWEpoch, AggregatorWEpochVault, RedeemParams, DepositParams, IVaultStrategy, AuthConfig, FeeConfig } from "vaults/sectorVaults/AggregatorWEpochVault.sol";
import { BatchedWithdrawEpoch } from "../../common/BatchedWithdrawEpoch.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { EAction } from "interfaces/Structs.sol";
import { VaultType } from "interfaces/Structs.sol";
import { Accounting } from "../../common/Accounting.sol";
import { SectorErrors } from "interfaces/SectorErrors.sol";

import "hardhat/console.sol";

contract AggregatorWEpochVaultTest is SectorTest, SCYWEpochVaultUtils {
	SCYWEpochVault s1;
	SCYWEpochVault s2;
	AggregatorWEpochVault s3;

	IVaultStrategy strategy1;
	IVaultStrategy strategy2;
	IVaultStrategy strategy3;

	WETH underlying;

	AggregatorWEpochVault vault;

	function setUp() public {
		underlying = new WETH();

		s1 = setUpSCYVault(address(underlying));
		s2 = setUpSCYVault(address(underlying));
		s3 = new AggregatorWEpochVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		strategy1 = IVaultStrategy(address(s1));
		strategy2 = IVaultStrategy(address(s2));
		strategy3 = IVaultStrategy(address(s3));

		vault = new AggregatorWEpochVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
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

		vm.expectRevert(SectorBaseWEpoch.StrategyNotFound.selector);
		vault.removeStrategy(strategy2);

		vault.addStrategy(strategy2);
		assertEq(address(vault.strategyIndex(2)), address(strategy2));
		assertEq(vault.totalStrategies(), 3);

		vm.expectRevert(SectorBaseWEpoch.StrategyExists.selector);
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

		vm.expectRevert(BatchedWithdrawEpoch.NotReady.selector);
		vm.prank(user1);
		vault.redeem();

		sectCompleteRedeem(vault, user1);
		assertEq(vault.underlyingBalance(user1), (100e18 * 3) / 4, "3/4 of deposit remains");

		assertEq(underlying.balanceOf(user1), amnt / 4);

		// amount should reset
		vm.expectRevert(Accounting.ZeroAmount.selector);
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

		// sectHarvestRevert(vault, SectorBaseWEpoch.NotEnoughtFloat.selector);

		uint256 pendingWithdraw = vault.convertToAssets(vault.requestedRedeem());
		uint256 withdrawShares = (pendingWithdraw * strategy1.exchangeRateUnderlying()) / 1e18;

		withdrawFromStrat(strategy1, withdrawShares);

		sectHarvest(vault);

		sectCompleteRedeem(vault, user1);

		assertApproxEqRel(underlying.balanceOf(user1), amnt / 4 + 9e18 / 4, .00001e18);
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

		sectHarvest(vault);
		sectInitRedeem(vault, user1, 1e18);

		uint256 pendingWithdraw = vault.convertToAssets(vault.requestedRedeem());
		uint256 withdrawShares = (pendingWithdraw * strategy1.exchangeRateUnderlying()) / 1e18;

		withdrawFromStrat(strategy1, withdrawShares);

		vm.prank(user1);
		vault.cancelRedeem();

		(, uint256 shares) = vault.withdrawLedger(user1);
		assertEq(shares, 0);

		uint256 profit = ((10e18 + (mLp) / 10) * 9) / 10;
		uint256 profitFromBurn = (profit / 4);
		assertApproxEqRel(
			vault.underlyingBalance(user1),
			amnt / 4 + profitFromBurn,
			.001e18,
			"user balance"
		);
		assertEq(underlying.balanceOf(user1), 0);

		// amount should reset
		vm.expectRevert(Accounting.ZeroAmount.selector);
		vm.prank(user1);
		vault.redeem();
	}

	function testDepositWithdrawStrats() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt - mLp);

		sectDeposit3Strats(vault, 200e18, 300e18, 500e18);

		assertEq(vault.getTvl(), amnt);
		assertEq(vault.totalChildHoldings(), amnt);

		uint256 nStrats = vault.totalStrategies();
		IVaultStrategy[] memory strats = new IVaultStrategy[](nStrats);
		uint256[] memory redeemFract = new uint256[](nStrats);
		for (uint256 i = 0; i < nStrats; i++) {
			strats[i] = IVaultStrategy(vault.strategyIndex(i));
			redeemFract[i] = .5e18;
		}
		requestRedeemFromStrats(strats, redeemFract);

		skip(1);
		sectHarvest(s3);

		for (uint256 i = 0; i < nStrats; i++) {
			IVaultStrategy strat = IVaultStrategy(vault.strategyIndex(i));
			processRedeem(strat);
		}

		skip(1);
		vm.roll(block.number + 1);

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
		uint256 pendingWithdraw = vault.convertToAssets(vault.requestedRedeem());

		assertEq(pendingWithdraw, amnt / 2, "pending withdraw");
		sectHarvest(vault);

		vm.prank(manager);
		vault.processRedeem(0);

		assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float doesnt update on process redeem");

		DepositParams[] memory dParams = new DepositParams[](1);
		dParams[0] = (DepositParams(strategy1, VaultType.Strategy, amnt / 2, 0));

		vm.expectRevert(SectorBaseWEpoch.NotEnoughtFloat.selector);
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
		vm.stopPrank();

		// redeem
		scyWithdrawEpoch(s1, user1, 1e18);
		scyWithdrawEpoch(s2, user1, 1e18);
		sectRedeemEpoch(s3, user1, 1e18);

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
		vault = new AggregatorWEpochVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			true,
			type(uint256).max,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);
		sectDeposit(vault, owner, mLp);

		uint256 amnt = 1000e18;
		deal(self, amnt);
		vault.deposit{ value: amnt }(amnt, self);

		uint256 startSupply = vault.totalSupply();

		assertEq(vault.underlyingBalance(self), amnt);
		assertEq(self.balance, 0);

		uint256 shares = vault.balanceOf(self);
		vault.requestRedeem(shares, self);
		skip(1);
		sectHarvest(vault);
		vault.processRedeem(0);

		vault.redeemNative();

		assertEq(self.balance, amnt);
		assertEq(vault.totalSupply(), startSupply - shares, "supply should update");
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
		vm.expectRevert(SectorErrors.MaxTvlReached.selector);
		vault.deposit(1, user1);
		vm.stopPrank();
	}

	function testReedeemTwice() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt);

		sectInitRedeem(vault, user1, .5e18);
		sectHarvest(vault);
		sectCompleteRedeem(vault, user1);

		sectInitRedeem(vault, user1, 1e18);
		sectHarvest(vault);
		sectCompleteRedeem(vault, user1);

		assertEq(underlying.balanceOf(user1), amnt);
	}

	function testRedeemReqBeforeCompletion() public {
		uint256 amnt = 1000e18;
		sectDeposit(vault, user1, amnt);

		sectInitRedeem(vault, user1, .5e18);
		sectHarvest(vault);

		// TODO we can have this should fail?

		vm.startPrank(user1);
		uint256 sharesToWithdraw = vault.balanceOf(user1) / 2;
		vm.expectRevert(BatchedWithdrawEpoch.RedeemRequestExists.selector);
		vault.requestRedeem(sharesToWithdraw);
		vm.stopPrank();

		// deposit should work
		sectDeposit(vault, user2, amnt);

		sectCompleteRedeem(vault, user1);

		assertEq(underlying.balanceOf(user1), amnt / 2);
	}

	function testEmergencyRedeemEdgeCase() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);

		sectInitRedeem(vault, user1, .5e18);
		sectHarvest(vault);

		vm.prank(user1);
		vault.cancelRedeem();

		assertEq(vault.balanceOf(user1), amnt, "share balance full");

		sectInitRedeem(vault, user1, .5e18);

		assertEq(vault.balanceOf(user1), amnt / 2, "share balance half");

		sectHarvest(vault);

		vm.prank(user1);
		vault.emergencyRedeem();

		assertEq(vault.balanceOf(user1), 0, "share balance 0");
		assertEq(underlying.balanceOf(user1), amnt / 2);

		sectCompleteRedeem(vault, user1);
		assertEq(underlying.balanceOf(user1), amnt);
	}

	function testEmergencyRedeemEdgeCase2() public {
		uint256 amnt = 100e18;
		sectDeposit(vault, user1, amnt);
		sectDeposit(vault, user2, amnt);

		depositToStrat(strategy1, amnt);
		depositToStrat(strategy2, amnt);

		sectInitRedeem(vault, user1, .5e18);
		sectInitRedeem(vault, user2, .5e18);

		uint256 shares1 = strategy1.underlyingToShares(amnt / 2);
		withdrawFromStrat(strategy1, shares1);
		uint256 shares2 = strategy2.underlyingToShares(amnt / 2);
		withdrawFromStrat(strategy2, shares2);

		// sectHarvest(vault);
		vault.processRedeem(0);

		vm.prank(user1);
		vault.emergencyRedeem();

		sectCompleteRedeem(vault, user1);
		sectCompleteRedeem(vault, user2);

		vm.prank(user2);
		vault.emergencyRedeem();

		assertEq(vault.balanceOf(user1), 0, "share balance 0");
		assertEq(vault.balanceOf(user2), 0, "share balance 0");

		assertEq(s1.balanceOf(user1), s1.balanceOf(user2), "strat 1 balances");
		assertEq(s2.balanceOf(user1), s2.balanceOf(user2), "strat 1 balances");
		assertApproxEqAbs(
			underlying.balanceOf(user1),
			underlying.balanceOf(user2),
			1,
			"underlying balances"
		);
	}

	/// UTILS

	function depositToStrat(IVaultStrategy strategy, uint256 amount) public {
		DepositParams[] memory params = new DepositParams[](1);
		params[0] = (DepositParams(strategy, strategy.vaultType(), amount, 0));
		vault.depositIntoStrategies(params);
	}

	function withdrawFromStrat(IVaultStrategy strategy, uint256 amount) public {
		uint256 fract = ((1e18 * amount) / strategy.balanceOf(address(vault)));
		requestRedeemFromStrategy(strategy, fract);
		processRedeem(strategy);

		RedeemParams[] memory rParams = new RedeemParams[](1);
		rParams[0] = (RedeemParams(strategy, strategy.vaultType(), amount, 0));
		vault.withdrawFromStrategies(rParams);
	}

	function requestRedeemFromStrategy(IVaultStrategy strat, uint256 fraction) public {
		IVaultStrategy[] memory strats = new IVaultStrategy[](1);
		strats[0] = strat;
		uint256[] memory fracs = new uint256[](1);
		fracs[0] = fraction;
		requestRedeemFromStrats(strats, fracs);
	}

	function requestRedeemFromStrats(IVaultStrategy[] memory strats, uint256[] memory fraction)
		public
	{
		RedeemParams[] memory rParams = new RedeemParams[](strats.length);
		for (uint256 i = 0; i < strats.length; i++) {
			uint256 balance = strats[i].balanceOf(address(vault));
			uint256 redeem = (balance * fraction[i]) / 1e18;
			rParams[i] = (RedeemParams(strats[i], strats[i].vaultType(), redeem, 0));
		}
		vault.requestRedeemFromStrategies(rParams);
	}

	function sectHarvest(AggregatorWEpochVault _vault) public {
		vm.startPrank(manager);
		uint256 expectedTvl = _vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectHarvestRevert(AggregatorWEpochVault _vault, bytes4 err) public {
		vm.startPrank(manager);
		uint256 expectedTvl = vault.getTvl();
		uint256 maxDelta = expectedTvl / 1000; // .1%
		vm.expectRevert(err);
		_vault.harvest(expectedTvl, maxDelta);
		vm.stopPrank();
	}

	function sectRedeemEpoch(
		AggregatorWEpochVault _vault,
		address acc,
		uint256 faction
	) public {
		vm.startPrank(acc);
		uint256 balance = IERC20(address(strategy3)).balanceOf(user1);
		_vault.requestRedeem((faction * balance) / 1e18, acc);
		// sectHarvest(_vault);
		// skip(1);
		vm.stopPrank();
		vm.prank(manager);
		_vault.processRedeem(0);
		vm.prank(user1);
		strategy3.redeem();
	}

	function sectDeposit(
		AggregatorWEpochVault _vault,
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
		AggregatorWEpochVault _vault,
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

	function sectCompleteRedeem(AggregatorWEpochVault _vault, address acc) public {
		vm.prank(manager);
		_vault.processRedeem(0);

		assertTrue(vault.redeemIsReady(acc), "redeem ready");

		vm.prank(acc);
		_vault.redeem();
	}

	function sectDeposit3Strats(
		AggregatorWEpochVault _vault,
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
		AggregatorWEpochVault _vault,
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

	function processRedeem(IVaultStrategy _vault) public {
		uint256 shares = _vault.requestedRedeem();
		uint256 minAmountOut = (_vault.sharesToUnderlying(shares) * 9990) / 10000;
		vm.prank(manager);
		_vault.processRedeem(minAmountOut);
	}

	function testMultiRedeem() public {
		sectDeposit(vault, user1, 1e18);
		sectDeposit(vault, user2, 1e18);

		uint256 shares1 = vault.balanceOf(user1);
		vm.prank(user1);
		vault.requestRedeem(shares1);

		vault.processRedeem(0);

		vm.prank(user2);
		vault.requestRedeem(shares1);

		vault.processRedeem(0);

		vm.prank(user1);
		vault.redeem();

		vm.prank(user2);
		vault.redeem();

		assertTrue(vault.balanceOf(user1) == 0, "user1 balance");
		assertTrue(vault.balanceOf(user2) == 0, "user2 balance");
		assertEq(underlying.balanceOf(user1), 1e18, "user1 underlying");
		assertEq(underlying.balanceOf(user2), 1e18, "user2 underlying");
	}

	function testGetMaxTvl() public {
		vault.setMaxTvl(10e18);
		s1.setMaxTvl(1e18);
		s2.setMaxTvl(2e18);
		// s3.setMaxTvl(2e18); // maxTvl will be 0 because there is no strategy

		uint256 maxStratTvl = vault.getMaxTvl();
		uint256 maxTvl = vault.maxTvl();
		assertEq(maxStratTvl, 3e18, "max strat tvl");
		assertEq(maxTvl, 10e18, "max tvl");
	}
}
