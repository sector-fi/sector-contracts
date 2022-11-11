// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockScyVault, SCYVault, Strategy, AuthConfig, FeeConfig } from "../mocks/MockScyVault.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { ISuperComposableYield as ISCY } from "../../interfaces/ERC5115/ISuperComposableYield.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";

import "hardhat/console.sol";

contract SCYVaultSetup is SectorTest {
	address NATIVE = address(0); // SCY vault constant;
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 DEAFAULT_MANAGEMENT_FEE = 0;
	uint256 mLp = 1000; // MIN_LIQUIDITY constant

	function setUpSCYVault(address underlying) public returns (MockScyVault) {
		return setUpSCYVault(underlying, false);
	}

	function setUpSCYVault(address underlying, bool acceptsNativeToken)
		public
		returns (MockScyVault)
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

		MockScyVault vault = new MockScyVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			strategyConfig
		);
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

	function scyHarvest(SCYVault vault) public {
		return scyHarvest(vault, 0);
	}

	function scyHarvest(SCYVault vault, uint256 underlyingProfit) public {
		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
		params1[0].min = underlyingProfit;
		vault.harvest(vault.getTvl(), 0, params1, params2);
	}
}
