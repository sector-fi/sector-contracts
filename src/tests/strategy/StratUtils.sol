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
	uint256 minLp;

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
		// uint256 startTvl = strategy.getTotalTVL();
		uint256 startTvl = genericStrategy.getAndUpdateTVL();
		uint256 startAccBalance = vault.underlyingBalance(acc);
		deal(address(underlying), acc, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		underlying.approve(address(vault), amount);
		vault.deposit(acc, address(underlying), amount, (minSharesOut * 9930) / 10000);
		uint256 tvl = genericStrategy.getTotalTVL();
		uint256 endAccBalance = vault.underlyingBalance(acc);
		assertApproxEqAbs(tvl, startTvl + amount, (amount * 3) / 1000, "tvl should update");
		assertApproxEqAbs(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			(amount * 3) / 1000,
			"underlying balance"
		);
		// assertEq(underlying.balanceOf(address(genericStrategy)), 0);
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

	function moveUniPrice(uint256 fraction) public {
		moveUniswapPrice(uniPair, address(underlying), short, fraction);
	}

	function rebalance() public virtual;

	function harvest() public virtual;

	function noRebalance() public virtual;

	function adjustPrice(uint256 fraction) public virtual;
}
