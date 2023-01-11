// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockSCYWEpochVault, SCYWEpochVault, Strategy } from "../mocks/MockSCYWEpochVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { SCYWEpochVaultUtils } from "./SCYWEpochVaultUtils.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";

import "hardhat/console.sol";

contract SCYWEpochVaultTest is SectorTest, SCYWEpochVaultUtils {
	MockSCYWEpochVault vault;
	WETH underlying;

	function setUp() public {
		underlying = new WETH();
		vault = setUpSCYVault(address(underlying));
		scyPreDeposit(vault, address(this), vault.MIN_LIQUIDITY());
	}

	function testNativeFlow() public {
		uint256 amnt = 100e18;

		vm.startPrank(user1);
		vm.deal(user1, amnt);
		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit{ value: amnt }(user1, NATIVE, 0, (minSharesOut * 9930) / 10000);

		uint256 bal = vault.underlyingBalance(user1);
		assertEq(bal, amnt, "deposit balance");
		assertEq(user1.balance, 0, "eth balance");

		uint256 sharesToWithdraw = vault.balanceOf(user1);
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);

		vault.requestRedeem(sharesToWithdraw);
		vm.stopPrank();
		scyProcessRedeem(vault);
		vm.startPrank(user1);

		vault.redeem(user1, sharesToWithdraw, NATIVE, (minUnderlyingOut * 9930) / 10000);

		assertEq(vault.underlyingBalance(user1), 0, "deposit balance 0");
		assertEq(user1.balance, amnt, "eth balance");
		assertEq(address(vault).balance, 0, "vault eth balance");

		vm.stopPrank();
	}

	function testSCYDeposit() public {
		uint256 amnt = 100e18;
		scyDeposit(vault, user1, amnt);
	}

	function testManagerWithdraw() public {
		uint256 amnt = 100e18;
		scyDeposit(vault, user1, amnt);
		scyDeposit(vault, user2, amnt);

		uint256 withdrawShares = vault.totalSupply() / 2;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(withdrawShares);
		vault.withdrawFromStrategy(withdrawShares, minUnderlyingOut);

		uint256 b1 = vault.underlyingBalance(user1);
		uint256 b2 = vault.underlyingBalance(user2);
		assertEq(b1, amnt, "user1 balance");
		assertEq(b2, amnt, "user2 balance");

		scyWithdrawEpoch(vault, user1, 1e18);
		assertEq(underlying.balanceOf(user1), amnt);

		uint256 uBalance = underlying.balanceOf(address(vault));
		uint256 minSharesOut = vault.underlyingToShares(uBalance);
		vault.depositIntoStrategy(uBalance, minSharesOut);

		scyDeposit(vault, user3, amnt);
	}

	function testPerformanceFee() public {
		uint256 amnt = 100e18;
		scyDeposit(vault, user1, amnt);

		underlying.mint(address(vault.strategy()), 10e18 + (mLp) / 10); // 10% profit

		uint256 expectedTvl = vault.getTvl();
		assertEq(expectedTvl, 110e18 + mLp + (mLp) / 10, "expected tvl");

		scyHarvest(vault);

		assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
		assertApproxEqAbs(vault.underlyingBalance(user1), 109e18, mLp);
	}

	function testManagementFee() public {
		uint256 amnt = 100e18;
		scyDeposit(vault, user1, amnt);
		vault.setManagementFee(.01e18);

		skip(365 days);
		scyHarvest(vault);

		assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
		assertApproxEqAbs(vault.underlyingBalance(user1), 99e18, mLp);
	}

	function testGetBaseTokens() public {
		address[] memory baseTokens = vault.getBaseTokens();
		assertEq(baseTokens.length, 1, "base tokens length");
		assertEq(baseTokens[0], address(underlying), "base token");

		SCYWEpochVault nativeVault = setUpSCYVault(address(underlying), true);

		address[] memory baseTokensNative = nativeVault.getBaseTokens();
		assertEq(baseTokensNative.length, 2, "base tokens length");
		assertEq(baseTokensNative[0], address(underlying), "base token");
		assertEq(baseTokensNative[1], address(0), "native base token");
	}

	function testNativeDepWith() public {
		uint256 amnt = 100e18;

		vm.startPrank(user1);
		vm.deal(user1, amnt);
		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit{ value: amnt }(user1, NATIVE, 0, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		scyDeposit(vault, user2, amnt);

		vm.startPrank(user2);
		uint256 sharesToWithdraw2 = vault.balanceOf(user2);
		vault.requestRedeem(sharesToWithdraw2);
		vm.stopPrank();
		scyProcessRedeem(vault);
		vm.startPrank(user2);
		uint256 minUnderlyingOut2 = vault.sharesToUnderlying(sharesToWithdraw2);
		vault.redeem(user2, sharesToWithdraw2, NATIVE, (minUnderlyingOut2 * 9930) / 10000);
		vm.stopPrank();

		vm.startPrank(user1);

		uint256 sharesToWithdraw = vault.balanceOf(user1);
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.requestRedeem(sharesToWithdraw);
		vm.stopPrank();
		scyProcessRedeem(vault);
		vm.startPrank(user1);
		vault.redeem(user1, sharesToWithdraw, NATIVE, (minUnderlyingOut * 9930) / 10000);

		assertEq(vault.underlyingBalance(user1), 0, "deposit balance 0");
		assertEq(user1.balance, amnt, "eth balance");

		assertEq(vault.underlyingBalance(user2), 0, "deposit balance 0");
		assertEq(user2.balance, amnt, "eth balance");

		assertEq(address(vault).balance, 0, "vault eth balance");

		vm.stopPrank();
	}

	function testEmptyHarvest() public {
		uint256 amnt = 100e18;
		scyDeposit(vault, user1, amnt);

		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](0);
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
		(uint256[] memory h1, uint256[] memory h2) = vault.harvest(
			vault.getTvl(),
			0,
			params1,
			params2
		);
		assertEq(h1.length, 0, "harvest 1 length");
		assertEq(h2.length, 0, "harvest 1 length");
	}

	function testMisconfiguration() public {
		// NATIVE deposits and withdrawals will fail with an ERC20 token as underlying
		MockERC20 testToken = new MockERC20("TEST", "TEST", 18);
		// WETH testToken = new WETH();

		vault = setUpSCYVault(address(testToken));
		scyDeposit(vault, address(this), vault.MIN_LIQUIDITY());

		uint256 amount = 10e18;

		// deposit native tokens
		vm.startPrank(user1);
		vm.deal(user1, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		vm.expectRevert();
		vault.deposit{ value: amount }(user1, NATIVE, 0, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		// user2 deposits underlying tokens
		scyDeposit(vault, user2, amount);

		vm.startPrank(user2);
		vm.expectRevert();
		vault.redeem(user2, amount, NATIVE, 0);
		vm.stopPrank();
	}

	function testMultiRedeem() public {
		uint256 amnt = 100e18;
		scyPreDeposit(vault, user1, amnt);
		scyPreDeposit(vault, user2, amnt);

		uint256 sharesToWithdraw1 = vault.balanceOf(user1);
		uint256 sharesToWithdraw2 = vault.balanceOf(user2);

		uint256 minUnderlyingOut1 = vault.sharesToUnderlying(sharesToWithdraw1);
		uint256 minUnderlyingOut2 = vault.sharesToUnderlying(sharesToWithdraw2);

		vm.prank(user1);
		vault.requestRedeem(sharesToWithdraw1);

		scyProcessRedeem(vault);

		vm.prank(user2);
		vault.requestRedeem(sharesToWithdraw2);

		scyProcessRedeem(vault);

		scyDeposit(vault, user3, amnt);
		uint256 assets = vault.totalAssets();
		uint256 shares = vault.convertToShares(assets);
		uint256 minAmountOut = vault.sharesToUnderlying(shares);

		vault.withdrawFromStrategy(shares, (minAmountOut * 999) / 1000);

		assertEq(vault.totalAssets(), 0, "total assets 0");
		assertEq(vault.uBalance(), amnt + mLp, "float balance");

		uint256 uBalance = vault.uBalance();
		uint256 minSharesOut = vault.underlyingToShares(vault.uBalance());
		vault.depositIntoStrategy(uBalance, (minSharesOut * 999) / 1000);

		vm.prank(user1);
		vault.redeem(
			user1,
			sharesToWithdraw1,
			address(underlying),
			(minUnderlyingOut1 * 9930) / 10000
		);

		vm.prank(user2);
		vault.redeem(
			user2,
			sharesToWithdraw2,
			address(underlying),
			(minUnderlyingOut2 * 9930) / 10000
		);

		assertEq(vault.underlyingBalance(user1), 0, "deposit balance1 0");
		assertEq(vault.underlyingBalance(user2), 0, "deposit balance2 0");

		assertEq(underlying.balanceOf(user1), amnt, "withdrawn amount1");
		assertEq(underlying.balanceOf(user2), amnt, "withdrawn amount2");
	}

	function testEarlyLifecycle() public {
		uint256 amnt = 100e18;
		scyPreDeposit(vault, user1, amnt);
		scyPreDeposit(vault, user2, amnt);

		assertEq(vault.balanceOf(user1), amnt, "user1 shares");
		assertEq(vault.balanceOf(user2), amnt, "user2 shares");
		assertEq(vault.underlyingBalance(user1), amnt, "user1 underlying");
		assertEq(vault.underlyingBalance(user2), amnt, "user2 underlying");
	}
}
