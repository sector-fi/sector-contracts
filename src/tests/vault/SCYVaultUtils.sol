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
import { SCYVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultU } from "vaults/ERC5115/SCYVaultU.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import { SectorFactory, UpgradeableBeacon } from "../../SectorFactory.sol";
import { ISCYVault } from "interfaces/ERC5115/ISCYVault.sol";

import "../../SectorBeaconProxy.sol";

import "hardhat/console.sol";

contract SCYVaultUtils is SectorTest {
	address NATIVE = address(0); // SCY vault constant;
	uint256 DEFAULT_PERFORMANCE_FEE = .1e18;
	uint256 DEAFAULT_MANAGEMENT_FEE = 0;
	uint256 mLp = 1000; // MIN_LIQUIDITY constant

	SectorFactory private factory;
	string private vaultType = "SCYVault";

	function setupFactory() public {
		factory = new SectorFactory();
		SCYVaultU vaultImp = new SCYVaultU();
		UpgradeableBeacon beacon = new UpgradeableBeacon(address(vaultImp));
		factory.addVaultType(vaultType, address(beacon));
	}

	function setUpSCYVault(address underlying) public returns (SCYVault) {
		return setUpSCYVault(underlying, false);
	}

	function setUpSCYVault(address underlying, bool acceptsNativeToken) public returns (SCYVault) {
		MockERC20 yieldToken = new MockERC20("Strat", "Strat", 18);

		SCYVaultConfig memory vaultConfig;

		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = address(yieldToken);
		vaultConfig.underlying = IERC20(underlying);
		vaultConfig.maxTvl = type(uint128).max;
		vaultConfig.acceptsNativeToken = acceptsNativeToken;

		SCYVault vault = new SCYVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			vaultConfig
		);

		MockScyStrategy strategy = new MockScyStrategy(
			address(vault),
			address(yieldToken),
			underlying
		);

		vault.initStrategy(address(strategy));

		return vault;
	}

	function setUpSCYVaultU(address underlying, bool acceptsNativeToken)
		public
		returns (SCYVaultU)
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
			SCYVaultU.initialize.selector,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			vaultConfig
		);

		SCYVaultU vault = SCYVaultU(payable(factory.deployVault(vaultType, data)));

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

		uint256 minSharesOut = vault.underlyingToShares(amnt);
		vault.deposit(acc, address(underlying), 0, (minSharesOut * 9930) / 10000);

		vm.stopPrank();
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
