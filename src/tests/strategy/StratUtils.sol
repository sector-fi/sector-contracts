// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../utils/PriceUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { HLPConfig, HarvestSwapParms } from "interfaces/Structs.sol";
import { SCYVault } from "vaults/scy/SCYVault.sol";
import { HLPCore } from "strategies/hlp/HLPCore.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { MasterChefCompMulti } from "strategies/hlp/implementations/MasterChefCompMulti.sol";
import { IStrategy } from "interfaces/IStrategy.sol";

import "hardhat/console.sol";

abstract contract StratUtils is SectorTest, PriceUtils {
	using UniUtils for IUniswapV2Pair;

	uint256 BASIS = 10000;
	uint256 mLp;

	SCYVault vault;

	HarvestSwapParms harvestParams;
	HarvestSwapParms harvestLendParams;

	IERC20 underlying;
	IUniswapV2Pair uniPair;
	address short;
	IStrategy genericStrategy;

	function configureUtils(
		address _underlying,
		address _short,
		address _uniPair,
		address _strategy
	) public {
		underlying = IERC20(_underlying);
		short = _short;
		uniPair = IUniswapV2Pair(_uniPair);
		genericStrategy = IStrategy(_strategy);
	}

	function deposit(uint256 amount) public {
		deposit(amount, address(this));
	}

	function deposit(uint256 amount, address acc) public {
		uint256 startTvl = vault.getAndUpdateTvl();
		uint256 startAccBalance = vault.underlyingBalance(acc);
		deal(address(underlying), acc, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		underlying.approve(address(vault), amount);
		vault.deposit(acc, address(underlying), amount, (minSharesOut * 9930) / 10000);
		uint256 tvl = vault.getAndUpdateTvl();
		uint256 endAccBalance = vault.underlyingBalance(acc);
		assertApproxEqRel(tvl, startTvl + amount, .01e18, "tvl should update");
		assertApproxEqRel(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			.01e18,
			"underlying balance"
		);
		// assertEq(vault.getStrategyTvl(), 0);
	}

	function withdraw(uint256 fraction) public {
		uint256 sharesToWithdraw = (vault.balanceOf(address(this)) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(
			address(this),
			sharesToWithdraw,
			address(underlying),
			(minUnderlyingOut * 9990) / 10000
		);
	}

	function withdrawCheck(uint256 fraction) public {
		uint256 startTvl = vault.getAndUpdateTvl(); // us updates iterest
		withdraw(fraction);
		uint256 tvl = vault.getAndUpdateTvl();
		assertApproxEqAbs(tvl, (startTvl * (1e18 - fraction)) / 1e18, mLp + 10, "tvl");
		assertApproxEqAbs(vault.underlyingBalance(address(this)), tvl, mLp + 10, "tvl balance");
	}

	function withdrawAll() public {
		uint256 balance = vault.balanceOf(address(this));

		vault.redeem(address(this), balance, address(underlying), 0);

		uint256 tvl = vault.getStrategyTvl();
		assertApproxEqAbs(tvl, 0, mLp, "strategy tvl");
		assertEq(vault.balanceOf(address(this)), 0, "account shares");
		assertEq(vault.underlyingBalance(address(this)), 0, "account value");
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

	function moveUniPrice(uint256 fraction) public virtual {
		if (address(uniPair) == address(0)) return;
		moveUniswapPrice(uniPair, address(underlying), short, fraction);
	}

	function rebalance() public virtual;

	function harvest() public virtual;

	function noRebalance() public virtual;

	function adjustPrice(uint256 fraction) public virtual;
}
