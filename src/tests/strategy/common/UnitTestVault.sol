// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { MockERC20 } from "../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { SCYStratUtils } from "./SCYStratUtils.sol";
import { StratAuthTest } from "../common/StratAuthTest.sol";
import { Auth, AuthConfig } from "../../../common/Auth.sol";

import "hardhat/console.sol";

abstract contract UnitTestVault is SCYStratUtils, StratAuthTest {
	/*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/
	function testGetTvl() public {
		uint256 tvl = vault.getTvl();
		assertEq(tvl, 0);
	}

	function testDepositFuzz(uint256 fuzz) public {
		uint256 min = getAmnt() / 100;
		fuzz = bound(fuzz, min, vault.getMaxTvl() - mLp);
		deposit(user1, fuzz);
		assertApproxEqRel(vault.underlyingBalance(user1), fuzz, .0011e18);
	}

	function testDepositWithdrawPartial(uint256 fuzz) public {
		uint256 depAmnt = getAmnt();
		uint256 min = depAmnt / 10000;
		uint256 wAmnt = bound(fuzz, min, depAmnt);

		deposit(user1, depAmnt);
		withdrawAmnt(user1, wAmnt);

		assertApproxEqRel(underlying.balanceOf(user1), wAmnt, .001e18);
		withdrawAmnt(user1, depAmnt - wAmnt);

		// price should not be off by more than 1%
		assertApproxEqRel(underlying.balanceOf(user1), depAmnt, .001e18);
	}

	function testDepositWithdraw99Percent(uint256 fuzz) public {
		// deposit fixed amount, withdraw between 99% and 100% of balance
		uint256 depAmnt = getAmnt();
		uint256 wAmnt = bound(fuzz, (depAmnt * 99) / 100, depAmnt);

		deposit(user1, depAmnt);
		withdrawAmnt(user1, wAmnt);

		assertApproxEqRel(underlying.balanceOf(user1), wAmnt, .001e18);
		withdrawAmnt(user1, depAmnt - wAmnt);

		assertApproxEqRel(underlying.balanceOf(user1), depAmnt, .001e18);
	}

	function testWithdrawWithNoBalance() public {
		withdrawAmnt(user1, 1e18);
		assertEq(underlying.balanceOf(user1), 0);
	}

	function testWithdrawMoreThanBalance() public {
		deposit(user1, dec);
		withdrawAmnt(user1, 2 * dec);
		assertApproxEqRel(underlying.balanceOf(user1), dec, .0015e18);
	}

	function testCloseVaultPosition() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		vm.prank(guardian);
		vault.closePosition(0, 0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .005e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
	}

	function testAccounting() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 startBalance = vault.underlyingBalance(user1);
		adjustPrice(1.2e18);
		deposit(user2, amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(user2),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		adjustPrice(.834e18);
		uint256 balance = vault.underlyingBalance(user1);
		assertApproxEqRel(balance, startBalance, .001e18, "first balance should not decrease");
	}

	function testManagerWithdraw() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		uint256 shares = IERC20(address(vault)).totalSupply();
		vm.prank(guardian);
		vault.withdrawFromStrategy(shares, 0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqRel(floatBalance, amnt, .001e18);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
		vm.roll(block.number + 1);
		vm.prank(guardian);
		vault.depositIntoStrategy(floatBalance, 0);
	}

	function testLpToken() public virtual {
		assertEq(vault.yieldToken(), vault.strategy().getLpToken());
	}

	function testSlippage() public virtual {
		uint256 amount = getAmnt();
		deposit(user2, amount);
		uint256 shares = vault.underlyingToShares(amount);
		uint256 actualShares = getEpochVault(vault).getDepositAmnt(amount);
		assertApproxEqRel(shares, actualShares, .001e18, "deposit shares");
		deposit(user1, amount);
		assertApproxEqRel(IERC20(address(vault)).balanceOf(user1), actualShares, .01e18);

		uint256 balance = vault.underlyingBalance(user1);
		shares = IERC20(address(vault)).balanceOf(user1);
		uint256 actualBalance = getEpochVault(vault).getWithdrawAmnt(shares);
		assertApproxEqRel(actualBalance, balance, .001e18, "withdraw shares");
	}

	function testOwnershipTransfer() public {
		Auth _vault = Auth(address(vault));
		_vault.transferOwnership(user1);
		assertEq(_vault.owner(), address(this));
		vm.prank(user1);
		_vault.acceptOwnership();
		assertEq(_vault.owner(), user1);
	}

	function testZeroStratRedeem() public {
		uint256 amnt = getAmnt();
		deposit(user1, amnt);
		vm.prank(manager);
		vault.closePosition(0, 0);
		// we should handle this gracefully
		vault.getDepositAmnt(amnt);
		withdraw(user1, 1e18);
	}
}
