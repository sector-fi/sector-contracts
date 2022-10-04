// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockScyVault, SCYVault, Strategy } from "../mocks/MockScyVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";

import "hardhat/console.sol";

contract SCYVaultTest is SectorTest {
	MockScyVault vault;
	MockERC20 strategy;
	WETH underlying;

	address NATIVE = address(0); // SCY vault constant;

	address manager = address(101);
	address guardian = address(102);
	address treasury = address(103);
	address owner = address(this);

	address user1 = address(201);
	address user2 = address(202);
	address user3 = address(203);

	Strategy strategyConfig;

	function setUp() public {
		strategy = new MockERC20("Strat", "Strat", 18);
		underlying = new WETH();

		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = address(strategy);
		strategyConfig.addr = address(strategy);
		strategyConfig.underlying = IERC20(underlying);
		strategyConfig.maxTvl = type(uint128).max;
		strategyConfig.treasury = treasury;
		strategyConfig.performanceFee = .1e18;

		vault = new MockScyVault(owner, guardian, manager, strategyConfig);

		deposit(address(this), vault.MIN_LIQUIDITY());
	}

	function testNativeFlow() public {
		uint256 amnt = 100e18;

		vm.startPrank(user1);
		vm.deal(user1, amnt);
		SafeETH.safeTransferETH(address(vault), amnt);
		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit(user1, NATIVE, 0, (minSharesOut * 9930) / 10000);

		uint256 bal = vault.underlyingBalance(user1);
		assertEq(bal, amnt, "deposit balance");
		assertEq(user1.balance, 0, "eth balance");

		uint256 sharesToWithdraw = vault.balanceOf(user1);
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(user1, sharesToWithdraw, NATIVE, (minSharesOut * 9930) / 10000);

		assertEq(vault.underlyingBalance(user1), 0, "deposit balance 0");
		assertEq(user1.balance, amnt, "eth balance");
		assertEq(address(vault).balance, 0, "vault eth balance");

		vm.stopPrank();
	}

	function testSCYDeposit() public {
		uint256 amnt = 100e18;
		deposit(user1, amnt);
	}

	function testManagerWithdraw() public {
		uint256 amnt = 100e18;
		deposit(user1, amnt);
		deposit(user2, amnt);

		uint256 withdrawShares = vault.totalSupply() / 2;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(withdrawShares);
		vault.withdrawFromStrategy(withdrawShares, minUnderlyingOut);

		uint256 b1 = vault.underlyingBalance(user1);
		uint256 b2 = vault.underlyingBalance(user2);
		assertEq(b1, amnt, "user1 balance");
		assertEq(b2, amnt, "user2 balance");

		withdraw(user1, 1e18);
		assertEq(underlying.balanceOf(user1), amnt);

		underlying.mint(user2, amnt);
		vm.startPrank(user2);
		underlying.approve(address(vault), amnt);
		vm.expectRevert(SCYVault.DepositsPaused.selector);
		vault.deposit(user2, address(underlying), amnt, 0);
		vm.stopPrank();

		uint256 uBalance = underlying.balanceOf(address(vault));
		uint256 minSharesOut = vault.underlyingToShares(uBalance);
		vault.depositIntoStrategy(uBalance, minSharesOut);

		deposit(user3, amnt);
	}

	function deposit(address acc, uint256 amnt) public {
		vm.startPrank(acc);
		underlying.mint(acc, amnt);
		if (vault.sendERC20ToStrategy()) underlying.transfer(vault.strategy(), amnt);
		else underlying.transfer(address(vault), amnt);

		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit(acc, address(underlying), 0, (minSharesOut * 9930) / 10000);

		vm.stopPrank();
	}

	function withdraw(address acc, uint256 fraction) public {
		vm.startPrank(acc);

		uint256 sharesToWithdraw = (vault.balanceOf(acc) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(acc, sharesToWithdraw, address(underlying), minUnderlyingOut);

		vm.stopPrank();
	}
}
