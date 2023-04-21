// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";

import { SectorTest } from "../../utils/SectorTest.sol";
import { HLPConfig, HarvestSwapParams } from "interfaces/Structs.sol";
import { SCYBase } from "vaults/ERC5115/SCYBase.sol";
import { HLPCore } from "strategies/hlp/HLPCore.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { Auth, AuthConfig } from "../../../common/Auth.sol";
import { SCYWEpochVault } from "vaults/ERC5115/SCYWEpochVault.sol";
import { ISCYVault } from "interfaces/ERC5115/ISCYVault.sol";
import { SCYVault } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultU } from "vaults/ERC5115/SCYVaultU.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";
import { FeeConfig } from "../../../common/Fees.sol";
import { SectorFactory, SectorBeacon } from "../../../SectorFactory.sol";
import { SCYWEpochVaultU } from "vaults/ERC5115/SCYWEpochVaultU.sol";

import "hardhat/console.sol";

abstract contract SCYStratUtils is SectorTest {
	uint256 BASIS = 10000;
	uint256 mLp;
	uint256 redeemSlippage;

	HarvestSwapParams harvestParams;
	HarvestSwapParams harvestLendParams;

	IERC20 underlying;
	IStrategy strat;
	ISCYVault vault;

	uint256 dec;
	bytes32 GUARDIAN;
	bytes32 MANAGER;

	function configureUtils(address _underlying, address _strategy) public {
		underlying = IERC20(_underlying);
		strat = IStrategy(_strategy);
		dec = 10**underlying.decimals();
		GUARDIAN = Auth(payable(address(vault))).GUARDIAN();
		MANAGER = Auth(payable(address(vault))).MANAGER();
	}

	// function deploySCYVault(
	// 	AuthConfig memory authConfig,
	// 	FeeConfig memory feeConfig,
	// 	SCYVaultConfig memory vaultConfig
	// ) public returns (ISCYVault) {
	// 	return new SCYVault(authConfig, feeConfig, vaultConfig);
	// }

	function deploySCYVault(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		SCYVaultConfig memory vaultConfig
	) public returns (ISCYVault) {
		SectorFactory factory = new SectorFactory();
		SCYVaultU vaultImp = new SCYVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory.addVaultType("SCYVault", address(beacon));
		bytes memory data = abi.encodeWithSelector(
			SCYVaultU.initialize.selector,
			authConfig,
			feeConfig,
			vaultConfig
		);
		return SCYVaultU(payable(factory.deployVault("SCYVault", data)));
	}

	function deploySCYWEpochVault(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		SCYVaultConfig memory vaultConfig
	) public returns (ISCYVault) {
		SectorFactory factory = new SectorFactory();
		SCYWEpochVaultU vaultImp = new SCYWEpochVaultU();
		SectorBeacon beacon = new SectorBeacon(address(vaultImp));
		factory.addVaultType("SCYWEpochVault", address(beacon));
		bytes memory data = abi.encodeWithSelector(
			SCYVaultU.initialize.selector,
			authConfig,
			feeConfig,
			vaultConfig
		);
		return SCYWEpochVaultU(payable(factory.deployVault("SCYWEpochVault", data)));
	}

	function deposit(uint256 amount) public {
		deposit(address(this), amount);
	}

	function depositRevert(
		address user,
		uint256 amnt,
		bytes4 err
	) public {
		skip(1);
		deal(address(underlying), user, amnt);
		vm.startPrank(user);
		underlying.approve(address(vault), amnt);
		vm.expectRevert(err);
		vault.deposit(user, address(underlying), amnt, 0);
		vm.stopPrank();
		skip(1);
	}

	function deposit(address user, uint256 amount) public virtual {
		skip(3);
		uint256 startTvl = vault.getAndUpdateTvl();
		uint256 startAccBalance = vault.underlyingBalance(user);
		deal(address(underlying), user, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);

		uint256 startShares = IERC20(address(vault)).balanceOf(user);

		vm.startPrank(user);
		underlying.approve(address(vault), amount);
		vault.deposit(user, address(underlying), amount, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		uint256 tvl = vault.getAndUpdateTvl();
		uint256 endAccBalance = vault.underlyingBalance(user);

		assertApproxEqRel(
			IERC20(address(vault)).balanceOf(user) - startShares,
			minSharesOut,
			.01e18,
			"min estimate should be close"
		);

		assertApproxEqRel(tvl, startTvl + amount, .0015e18, "tvl should update");
		assertApproxEqRel(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			.01e18,
			"underlying balance"
		);
		assertEq(vault.getFloatingAmount(address(underlying)), 0);

		// this is necessary for stETH strategy (so closing account doesn't happen in same block)
		vm.roll(block.number + 1);
		skip(3);
	}

	function withdrawAmnt(address user, uint256 amnt) public {
		uint256 balance = vault.underlyingBalance(user);
		if (balance == 0) return;
		if (amnt > balance) amnt = balance;
		withdraw(user, (1e18 * amnt) / balance);
	}

	function withdraw(address user, uint256 fraction) public {
		skip(1);
		uint256 sharesToWithdraw = (IERC20(address(vault)).balanceOf(user) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vm.prank(user);
		vault.redeem(
			user,
			sharesToWithdraw,
			address(underlying),
			(minUnderlyingOut * 9990) / 10000
		);
		skip(1);
	}

	function withdrawEpoch(address user, uint256 fraction) public {
		requestRedeem(user, fraction);
		uint256 shares = SCYWEpochVault(payable(address(vault))).requestedRedeem();
		uint256 minAmountOut = vault.sharesToUnderlying(shares);
		SCYWEpochVault(payable(address(vault))).processRedeem((minAmountOut * 9990) / 10000);
		redeemShares(user, shares);
	}

	function requestRedeem(address user, uint256 fraction) public {
		uint256 sharesToWithdraw = (IERC20(address(vault)).balanceOf(user) * fraction) / 1e18;
		vm.prank(user);
		SCYWEpochVault(payable(address(vault))).requestRedeem(sharesToWithdraw);
	}

	function getEpochVault(ISCYVault _vault) public pure returns (SCYWEpochVault) {
		return SCYWEpochVault(payable(address(_vault)));
	}

	function withdrawCheck(address user, uint256 fraction) public {
		uint256 startTvl = vault.getAndUpdateTvl(); // us updates iterest
		uint256 startBal = underlying.balanceOf(user);
		withdraw(user, fraction);
		uint256 tvl = vault.getAndUpdateTvl();
		uint256 lockedTvl = vault.sharesToUnderlying(mLp);
		assertApproxEqRel(
			tvl,
			lockedTvl + (startTvl * (1e18 - fraction)) / 1e18,
			.0001e18,
			"vault tvl should update"
		);
		assertApproxEqRel(
			underlying.balanceOf(user) - startBal,
			startTvl - tvl,
			.001e18,
			"user should get underlying"
		);
	}

	function redeemShares(address user, uint256 shares) public {
		uint256 startTvl = vault.getAndUpdateTvl(); // this updates iterest
		uint256 minUnderlyingOut = vault.sharesToUnderlying(shares);
		uint256 userStartBal = underlying.balanceOf(user);

		vm.prank(user);
		vault.redeem(user, shares, address(underlying), (minUnderlyingOut * 9990) / 10000);
		uint256 tvl = vault.getAndUpdateTvl();
		uint256 lockedTvl = vault.sharesToUnderlying(mLp);
		assertApproxEqRel(
			tvl + 100000 + minUnderlyingOut,
			lockedTvl + (startTvl * (1e18 - redeemSlippage)) / 1e18 + 100000,
			.0011e18,
			"tvl should update"
		);
		assertApproxEqRel(
			underlying.balanceOf(user) - userStartBal,
			startTvl - tvl,
			.001e18,
			"user should get underlying"
		);
	}

	function withdrawAll(address user) public {
		skip(7 days);

		uint256 balance = IERC20(address(vault)).balanceOf(user);

		vm.prank(user);
		vault.redeem(user, balance, address(underlying), 0);

		uint256 fees = vault.underlyingBalance(treasury);

		uint256 tvl = vault.getStrategyTvl();

		assertApproxEqAbs(tvl, fees, vault.sharesToUnderlying(mLp) + 10, "strategy tvl");

		assertEq(IERC20(address(vault)).balanceOf(user), 0, "account shares");
		assertEq(vault.underlyingBalance(user), 0, "account value");

		skip(1);
	}

	function logTvl(IStrategy _strategy) internal view {
		(
			uint256 tvl,
			uint256 collateralBalance,
			uint256 shortPosition,
			uint256 borrowBalance,
			uint256 lpBalance,
			uint256 underlyingBalance
		) = _strategy.getTVL();
		console.log("tvl", tvl);
		console.log("collateralBalance", collateralBalance);
		console.log("shortPosition", shortPosition);
		console.log("borrowBalance", borrowBalance);
		console.log("lpBalance", lpBalance);
		console.log("underlyingBalance", underlyingBalance);
	}

	function rebalance() public virtual;

	function harvest() public virtual;

	function noRebalance() public virtual;

	function adjustPrice(uint256 fraction) public virtual;

	// slippage in basis points only used by hlp strat
	function priceSlippageParam() public view virtual returns (uint256) {
		return 0;
	}

	function getAmnt() public view virtual returns (uint256) {
		if (vault.acceptsNativeToken()) return 1e18;
		uint256 d = vault.underlyingDecimals();
		if (d == 6) return 100e6;
		if (d == 18) return 1e18;
	}
}
