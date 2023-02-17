// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { WETH } from "../mocks/WETH.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { ISuperComposableYield as ISCY } from "../../interfaces/ERC5115/ISuperComposableYield.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";

import { MockScyStrategy } from "../mocks/MockScyStrategy.sol";
import { SCYWEpochVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYWEpochVault.sol";
import { SCYWEpochVaultU } from "vaults/ERC5115/SCYWEpochVaultU.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import { SectorFactory, SectorBeacon } from "../../SectorFactory.sol";
import { ISCYVault } from "interfaces/ERC5115/ISCYVault.sol";
import "../../SectorBeaconProxy.sol";

import "hardhat/console.sol";

contract SCYWEpochVaultUtils is SectorTest {
	address NATIVE = address(0); // SCY vault constant;
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 DEAFAULT_MANAGEMENT_FEE = 0;
	uint256 mLp = 1000; // MIN_LIQUIDITY constant

	function setUpSCYVault(address underlying) public returns (SCYWEpochVault) {
		return setUpSCYVault(underlying, false);
	}

	SectorFactory private factory;
	string private vaultType = "SCYVWEpochVault";

	function setupFactory() public {
		factory = new SectorFactory();
		SCYWEpochVaultU vaultImp = new SCYWEpochVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory.addVaultType(vaultType, address(beacon));
	}

	function setUpSCYVault(address underlying, bool acceptsNativeToken)
		public
		returns (SCYWEpochVault)
	{
		MockERC20 yieldToken = new MockERC20("Strat", "Strat", 18);

		SCYVaultConfig memory vaultConfig;

		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = address(yieldToken);
		// vaultConfig.addr = address(strategy);
		vaultConfig.underlying = IERC20(underlying);
		vaultConfig.maxTvl = type(uint128).max;
		vaultConfig.acceptsNativeToken = acceptsNativeToken;

		SCYWEpochVault vault = new SCYWEpochVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			vaultConfig
		);

		MockScyStrategy strategy = new MockScyStrategy(
			address(vault),
			vaultConfig.yieldToken,
			underlying
		);
		vault.initStrategy(address(strategy));

		return vault;
	}

	function setUpSCYVaultU(address underlying, bool acceptsNativeToken)
		public
		returns (SCYWEpochVaultU)
	{
		MockERC20 yieldToken = new MockERC20("Strat", "Strat", 18);

		SCYVaultConfig memory vaultConfig;

		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = address(yieldToken);
		vaultConfig.underlying = IERC20(underlying);
		vaultConfig.maxTvl = type(uint128).max;
		vaultConfig.acceptsNativeToken = acceptsNativeToken;

		setupFactory();

		bytes memory data = abi.encodeWithSelector(
			SCYWEpochVaultU.initialize.selector,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			vaultConfig
		);

		SCYWEpochVaultU vault = SCYWEpochVaultU(payable(factory.deployVault(vaultType, data)));

		MockScyStrategy strategy = new MockScyStrategy(
			address(vault),
			address(yieldToken),
			underlying
		);

		vault.initStrategy(address(strategy));

		return vault;
	}

	function scyDeposit(
		ISCYVault vault,
		address acc,
		uint256 amnt
	) public {
		MockERC20 underlying = MockERC20(address(vault.underlying()));
		vm.startPrank(acc);
		underlying.mint(acc, amnt);
		if (vault.sendERC20ToStrategy()) underlying.transfer(address(vault.strategy()), amnt);
		else underlying.transfer(address(vault), amnt);

		uint256 minSharesOut = (vault.underlyingToShares(amnt) * 9930) / 10000;
		vault.deposit(acc, address(underlying), 0, minSharesOut);
		vm.stopPrank();
		if (vault.getStrategyTvl() == 0) {
			vm.prank(manager);
			vault.depositIntoStrategy(vault.uBalance(), minSharesOut);
		}
	}

	function scyPreDeposit(
		ISCYVault vault,
		address acc,
		uint256 amnt
	) public {
		MockERC20 underlying = MockERC20(address(vault.underlying()));
		vm.startPrank(acc);
		underlying.mint(acc, amnt);
		if (vault.sendERC20ToStrategy()) underlying.transfer(address(vault.strategy()), amnt);
		else underlying.transfer(address(vault), amnt);

		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit(acc, address(underlying), 0, (minSharesOut * 9930) / 10000);
		vm.stopPrank();
	}

	function scyWithdrawEpoch(
		ISCYVault vault,
		address user,
		uint256 fraction
	) public {
		requestRedeem(vault, user, fraction);
		scyProcessRedeem(vault);
		scyRedeem(vault, user);
	}

	function scyProcessRedeem(ISCYVault vault) public {
		uint256 shares = SCYWEpochVault(payable(address(vault))).requestedRedeem();
		uint256 minAmountOut = vault.sharesToUnderlying(shares);
		vm.prank(manager);
		SCYWEpochVault(payable(address(vault))).processRedeem(minAmountOut);
	}

	function requestRedeem(
		ISCYVault vault,
		address user,
		uint256 fraction
	) public {
		uint256 sharesToWithdraw = (IERC20(address(vault)).balanceOf(user) * fraction) / 1e18;
		vm.prank(user);
		SCYWEpochVault(payable(address(vault))).requestRedeem(sharesToWithdraw);
	}

	function scyRedeem(ISCYVault vault, address user) public {
		uint256 shares = SCYWEpochVault(payable(address(vault))).getRequestedShares(user);
		MockERC20 underlying = MockERC20(address(vault.underlying()));
		uint256 minUnderlyingOut = vault.sharesToUnderlying(shares);
		vm.prank(user);
		vault.redeem(user, shares, address(underlying), minUnderlyingOut);
	}

	function scyWithdraw(
		ISCYVault vault,
		address acc,
		uint256 fraction
	) public {
		MockERC20 underlying = MockERC20(address(vault.underlying()));

		vm.startPrank(acc);

		uint256 sharesToWithdraw = (IERC20(address(vault)).balanceOf(acc) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(acc, sharesToWithdraw, address(underlying), minUnderlyingOut);

		vm.stopPrank();
	}

	function scyHarvest(ISCYVault vault) public {
		return scyHarvest(vault, 0);
	}

	function scyHarvest(ISCYVault vault, uint256 underlyingProfit) public {
		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
		params1[0].min = underlyingProfit;
		vault.harvest(vault.getTvl(), 0, params1, params2);
	}
}
