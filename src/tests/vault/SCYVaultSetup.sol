// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockScyVault, SCYVault, Strategy } from "../mocks/MockScyVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { ISuperComposableYield as ISCY } from "../../interfaces/scy/ISuperComposableYield.sol";

import "hardhat/console.sol";

contract SCYVaultSetup is SectorTest {
	address NATIVE = address(0); // SCY vault constant;
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 mLp = 1000; // MIN_LIQUIDITY constant

	function setUpSCYVault(address underlying) public returns (MockScyVault) {
		MockERC20 strategy = new MockERC20("Strat", "Strat", 18);

		Strategy memory strategyConfig;

		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = address(strategy);
		strategyConfig.addr = address(strategy);
		strategyConfig.underlying = IERC20(underlying);
		strategyConfig.maxTvl = type(uint128).max;
		strategyConfig.treasury = treasury;
		strategyConfig.performanceFee = DEFAULT_PERFORMANCE_FEE;

		MockScyVault vault = new MockScyVault(owner, guardian, manager, strategyConfig);
		return vault;
	}

	function scyDeposit(
		SCYVault vault,
		address acc,
		uint256 amnt
	) public {
		MockERC20 underlying = MockERC20(address(vault.underlying()));
		vm.startPrank(acc);
		underlying.mint(acc, amnt);
		if (vault.sendERC20ToStrategy()) underlying.transfer(vault.strategy(), amnt);
		else underlying.transfer(address(vault), amnt);

		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit(acc, address(underlying), 0, (minSharesOut * 9930) / 10000);

		vm.stopPrank();
	}

	function scyWithdraw(
		SCYVault vault,
		address acc,
		uint256 fraction
	) public {
		MockERC20 underlying = MockERC20(address(vault.underlying()));

		vm.startPrank(acc);

		uint256 sharesToWithdraw = (vault.balanceOf(acc) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(acc, sharesToWithdraw, address(underlying), minUnderlyingOut);

		vm.stopPrank();
	}
}