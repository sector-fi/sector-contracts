// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockSCYWEpochVault, SCYWEpochVault, Strategy, AuthConfig, FeeConfig } from "../mocks/MockSCYWEpochVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { ISuperComposableYield as ISCY } from "../../interfaces/ERC5115/ISuperComposableYield.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";

import "hardhat/console.sol";

contract SCYWEpochVaultUtils is SectorTest {
	address NATIVE = address(0); // SCY vault constant;
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 DEAFAULT_MANAGEMENT_FEE = 0;
	uint256 mLp = 1000; // MIN_LIQUIDITY constant

	function setUpSCYVault(address underlying) public returns (MockSCYWEpochVault) {
		return setUpSCYVault(underlying, false);
	}

	function setUpSCYVault(address underlying, bool acceptsNativeToken)
		public
		returns (MockSCYWEpochVault)
	{
		MockERC20 strategy = new MockERC20("Strat", "Strat", 18);

		Strategy memory strategyConfig;

		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = address(strategy);
		strategyConfig.addr = address(strategy);
		strategyConfig.underlying = IERC20(underlying);
		strategyConfig.maxTvl = type(uint128).max;
		strategyConfig.acceptsNativeToken = acceptsNativeToken;

		MockSCYWEpochVault vault = new MockSCYWEpochVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			strategyConfig
		);
		return vault;
	}

	function scyDeposit(
		SCYWEpochVault vault,
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
		if (vault.getStrategyTvl() == 0) {
			vm.prank(manager);
			vault.depositIntoStrategy(vault.uBalance(), minSharesOut);
		}
	}

	function scyPreDeposit(
		SCYWEpochVault vault,
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

	function scyWithdrawEpoch(
		SCYWEpochVault vault,
		address user,
		uint256 fraction
	) public {
		requestRedeem(vault, user, fraction);
		scyProcessRedeem(vault);
		scyRedeem(vault, user);
	}

	function scyProcessRedeem(SCYWEpochVault vault) public {
		uint256 shares = vault.requestedRedeem();
		uint256 minAmountOut = vault.sharesToUnderlying(shares);
		vm.prank(manager);
		SCYWEpochVault(payable(vault)).processRedeem(minAmountOut);
	}

	function requestRedeem(
		SCYWEpochVault vault,
		address user,
		uint256 fraction
	) public {
		uint256 sharesToWithdraw = (vault.balanceOf(user) * fraction) / 1e18;
		vm.prank(user);
		vault.requestRedeem(sharesToWithdraw);
	}

	function scyRedeem(SCYWEpochVault vault, address user) public {
		uint256 shares = vault.getRequestedShares(user);
		MockERC20 underlying = MockERC20(address(vault.underlying()));
		uint256 minUnderlyingOut = vault.sharesToUnderlying(shares);
		vm.prank(user);
		vault.redeem(user, shares, address(underlying), minUnderlyingOut);
	}

	function scyWithdraw(
		SCYWEpochVault vault,
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

	function scyHarvest(SCYWEpochVault vault) public {
		return scyHarvest(vault, 0);
	}

	function scyHarvest(SCYWEpochVault vault, uint256 underlyingProfit) public {
		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
		params1[0].min = underlyingProfit;
		vault.harvest(vault.getTvl(), 0, params1, params2);
	}
}
