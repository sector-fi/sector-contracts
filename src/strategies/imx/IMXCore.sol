// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IBaseU, HarvestSwapParms } from "../mixins/upgradable/IBaseU.sol";
import { IIMXFarmU } from "../mixins/upgradable/IIMXFarmU.sol";
import { UniUtils, IUniswapV2Pair } from "../../libraries/UniUtils.sol";

import { IMXAuthU } from "./IMXAuthU.sol";

// import "hardhat/console.sol";

abstract contract IMXCore is
	Initializable,
	ReentrancyGuardUpgradeable,
	IMXAuthU,
	IBaseU,
	IIMXFarmU
{
	using UniUtils for IUniswapV2Pair;
	using SafeERC20 for IERC20;

	event Deposit(address sender, uint256 amount);
	event Redeem(address sender, uint256 amount);
	// event RebalanceLoan(address indexed sender, uint256 startLoanHealth, uint256 updatedLoanHealth);
	event SetRebalanceThreshold(uint256 rebalanceThreshold);
	event SetMaxTvl(uint256 maxTvl);
	// this determines our default leverage position
	event SetSafetyMarginSqrt(uint256 safetyMarginSqrt);

	event Harvest(uint256 harvested); // this is actual the tvl before harvest
	event Rebalance(uint256 shortPrice, uint256 tvlBeforeRebalance, uint256 positionOffset);
	event SetMaxPriceOffset(uint256 maxPriceOffset);

	uint256 constant MINIMUM_LIQUIDITY = 1000;
	uint256 constant BPS_ADJUST = 10000;
	uint256 constant MIN_LOAN_HEALTH = 1.02e18;

	IERC20 private _underlying;
	IERC20 private _short;

	uint256 private _maxTvl;
	uint16 public rebalanceThreshold = 400; // 4% of lp
	// price move before liquidation
	uint256 private _safetyMarginSqrt = 1.140175425e18; // sqrt of 130%
	uint256 public maxPriceOffset = .2e18;

	modifier checkPrice(uint256 expectedPrice, uint256 maxDelta) {
		// parameter validation
		// to prevent manipulation by manager
		if (!hasRole(GUARDIAN, msg.sender)) {
			uint256 oraclePrice = _shortToUnderlyingOracle(1e18);
			uint256 oracleDelta = oraclePrice > expectedPrice
				? oraclePrice - expectedPrice
				: expectedPrice - oraclePrice;
			if ((1e18 * (oracleDelta + maxDelta)) / expectedPrice > maxPriceOffset)
				revert OverMaxPriceOffset();
		}

		uint256 currentPrice = _shortToUnderlying(1e18);
		uint256 delta = expectedPrice > currentPrice
			? expectedPrice - currentPrice
			: currentPrice - expectedPrice;
		if (delta > maxDelta) revert SlippageExceeded();
		_;
	}

	function __IMX_init_(
		address vault_,
		address underlying_,
		address short_,
		uint256 maxTvl_
	) internal onlyInitializing {
		vault = vault_;
		_underlying = IERC20(underlying_);
		_short = IERC20(short_);

		_underlying.safeApprove(vault, type(uint256).max);

		// init default params
		// deployer is not owner so we set these manually
		_maxTvl = maxTvl_;
		emit SetMaxTvl(maxTvl_);

		// TODO param?
		rebalanceThreshold = 400;
		emit SetRebalanceThreshold(400);

		maxPriceOffset = .2e18;
		emit SetMaxPriceOffset(maxPriceOffset);

		_safetyMarginSqrt = 1.140175425e18;
		emit SetSafetyMarginSqrt(_safetyMarginSqrt);
	}

	// guardian can adjust max price offset if needed
	function setMaxPriceOffset(uint256 _maxPriceOffset) public onlyRole(GUARDIAN) {
		maxPriceOffset = _maxPriceOffset;
		emit SetMaxPriceOffset(_maxPriceOffset);
	}

	function safetyMarginSqrt() public view override returns (uint256) {
		return _safetyMarginSqrt;
	}

	function decimals() public view returns (uint8) {
		return IERC20Metadata(address(_underlying)).decimals();
	}

	// OWNER CONFIG

	function setRebalanceThreshold(uint16 rebalanceThreshold_) public onlyOwner {
		rebalanceThreshold = rebalanceThreshold_;
		emit SetRebalanceThreshold(rebalanceThreshold_);
	}

	function setSafetyMarginSqrt(uint256 safetyMarginSqrt_) public onlyOwner {
		_safetyMarginSqrt = safetyMarginSqrt_;
		emit SetSafetyMarginSqrt(_safetyMarginSqrt);
	}

	function setMaxTvl(uint256 maxTvl_) public onlyRole(GUARDIAN) {
		_maxTvl = maxTvl_;
		emit SetMaxTvl(maxTvl_);
	}

	// PUBLIC METHODS

	function short() public view override returns (IERC20) {
		return _short;
	}

	function underlying() public view override returns (IERC20) {
		return _underlying;
	}

	// deposit underlying and recieve lp tokens
	function deposit(uint256 underlyingAmnt) external onlyVault nonReentrant returns (uint256) {
		if (underlyingAmnt == 0) return 0; // cannot deposit 0
		uint256 tvl = getAndUpdateTVL();
		require(underlyingAmnt + tvl <= getMaxTvl(), "STRAT: OVER_MAX_TVL");
		uint256 startBalance = collateralToken().balanceOf(address(this));
		_increasePosition(underlyingAmnt);
		uint256 endBalance = collateralToken().balanceOf(address(this));
		return endBalance - startBalance;
	}

	// redeem lp for underlying
	function redeem(uint256 removeCollateral) public onlyVault returns (uint256 amountTokenOut) {
		// this is the full amount of LP tokens totalSupply of shares is entitled to
		_decreasePosition(removeCollateral);

		// TODO make sure we never have any extra underlying dust sitting around
		// all 'extra' underlying should allways be transferred back to the vault

		unchecked {
			amountTokenOut = _underlying.balanceOf(address(this));
		}
		emit Redeem(msg.sender, amountTokenOut);
	}

	// decreases position based to desired LP amount
	// ** does not rebalance remaining portfolio
	// ** make sure to update lending positions before calling this
	function _decreasePosition(uint256 removeCollateral) internal {
		(uint256 uBorrowBalance, uint256 sBorrowBalance) = _updateAndGetBorrowBalances();

		uint256 balance = collateralToken().balanceOf(address(this));
		uint256 lp = _getLiquidity(balance);

		// remove lp & repay underlying loan
		uint256 removeLp = (lp * removeCollateral) / balance;
		uint256 uRepay = (uBorrowBalance * removeCollateral) / balance;
		uint256 sRepay = removeCollateral == balance ? sBorrowBalance : type(uint256).max;

		_removeIMXLiquidity(removeLp, uRepay, sRepay);

		// make sure we are not close to liquidation
		if (loanHealth() < MIN_LOAN_HEALTH) revert LowLoanHealth();
	}

	// increases the position based on current desired balance
	// ** does not rebalance remaining portfolio
	function _increasePosition(uint256 amntUnderlying) internal {
		if (amntUnderlying < MINIMUM_LIQUIDITY) return; // avoid imprecision
		uint256 amntShort = _underlyingToShort(amntUnderlying);

		uint256 uBorrow = (_optimalUBorrow() * amntUnderlying) / 1e18;
		uint256 sBorrow = amntShort + _underlyingToShort(uBorrow);

		_addIMXLiquidity(amntUnderlying + uBorrow, sBorrow, uBorrow, sBorrow);
	}

	// MANAGER + OWNER METHODS
	// function increasePosition(
	// 	uint256 amount,
	// 	uint256 expectedPrice,
	// 	uint256 maxDelta
	// ) external checkPrice(expectedPrice, maxDelta) nonReentrant onlyRole(GUARDIAN) {
	// 	require(_underlying.balanceOf(address(this)) >= amount, "STRAT: NOT ENOUGH U");
	// 	_increasePosition(amount);
	// }

	// function decreasePosition(
	// 	uint256 collateralAmnt,
	// 	uint256 expectedPrice,
	// 	uint256 maxDelta
	// ) external checkPrice(expectedPrice, maxDelta) nonReentrant onlyRole(GUARDIAN) {
	// 	_decreasePosition(collateralAmnt);
	// }

	// use the return of the function to estimate pending harvest via staticCall
	function harvest(HarvestSwapParms calldata harvestParams)
		external
		onlyRole(MANAGER)
		nonReentrant
		returns (uint256 farmHarvest)
	{
		(uint256 startTvl, , , , , ) = getTVL();
		farmHarvest = _harvestFarm(harvestParams);

		// compound our lp position
		_increasePosition(_underlying.balanceOf(address(this)));
		emit Harvest(startTvl);
	}

	// There is not a situation where we would need this
	// function rebalanceLoan() public {
	// 	uint256 tvl = getOracleTvl();
	// 	uint256 tvl1 = getTotalTVL();

	// 	uint256 uBorrow = (tvl * _optimalUBorrow()) / 1e18;
	// 	(uint256 uBorrowBalance, ) = _getBorrowBalances();

	// 	if (uBorrowBalance <= uBorrow) return;
	// 	uint256 uRepay = uBorrowBalance - uBorrow;
	// 	(uint256 uLp, ) = _getLPBalances();

	// 	uint256 lp = _getLiquidity();

	// 	// remove lp & repay underlying loan
	// 	uint256 removeLp = (lp * uRepay) / uLp;
	// 	uint256 sRepay = type(uint256).max;
	// 	_removeIMXLiquidity(removeLp, uRepay, sRepay);
	// }

	function rebalance(uint256 expectedPrice, uint256 maxDelta)
		external
		onlyRole(MANAGER)
		checkPrice(expectedPrice, maxDelta)
		nonReentrant
	{
		// call this first to ensure we use an updated borrowBalance when computing offset
		uint256 tvl = getAndUpdateTVL();
		uint256 positionOffset = getPositionOffset();

		// don't rebalance unless we exceeded the threshold
		if (positionOffset <= rebalanceThreshold) revert RebalanceThreshold();

		if (tvl == 0) return;
		uint256 targetUBorrow = (tvl * _optimalUBorrow()) / 1e18;
		uint256 targetUnderlyingLP = tvl + targetUBorrow;

		(uint256 underlyingLp, uint256 shortLP) = _getLPBalances();
		uint256 targetShortLp = _underlyingToShort(targetUnderlyingLP);
		(uint256 uBorrowBalance, uint256 sBorrowBalance) = _updateAndGetBorrowBalances();

		// TODO account for uBalance
		// uint256 uBalance = underlying().balanceOf(address(this));

		if (underlyingLp > targetUnderlyingLP) {
			// TODO: we may need to borrow underlying

			uint256 uRepay = uBorrowBalance > targetUBorrow ? uBorrowBalance - targetUBorrow : 0;
			uint256 sRepay = sBorrowBalance > targetShortLp ? sBorrowBalance - targetShortLp : 0;

			// TODO check this
			uint256 lp = _getLiquidity();
			uint256 removeLp = lp - (lp * targetUnderlyingLP) / underlyingLp;
			_removeIMXLiquidity(removeLp, uRepay, sRepay);
		} else if (targetUnderlyingLP > underlyingLp) {
			uint256 uBorrow = targetUBorrow > uBorrowBalance ? targetUBorrow - uBorrowBalance : 0;
			uint256 sBorrow = targetShortLp > sBorrowBalance ? targetShortLp - sBorrowBalance : 0;

			// extra underlying balance will get re-paid automatically
			_addIMXLiquidity(
				targetUnderlyingLP - underlyingLp,
				targetShortLp - shortLP,
				uBorrow,
				sBorrow
			);
		}
		emit Rebalance(_shortToUnderlying(1e18), positionOffset, tvl);
	}

	// vault handles slippage
	function closePosition() public onlyVault returns (uint256 balance) {
		(uint256 uRepay, uint256 sRepay) = _updateAndGetBorrowBalances();
		uint256 removeLp = _getLiquidity();
		_removeIMXLiquidity(removeLp, uRepay, sRepay);
		// transfer funds to vault
		balance = _underlying.balanceOf(address(this));
		_underlying.safeTransfer(vault, balance);
	}

	// TVL

	function getMaxTvl() public view returns (uint256) {
		(, uint256 sBorrow) = _getBorrowBalances();
		uint256 availableToBorrow = sBorrowable().totalSupply() - sBorrowable().totalBorrows();
		return
			min(
				_maxTvl,
				// adjust the availableToBorrow to account for leverage
				_shortToUnderlying(
					sBorrow + (availableToBorrow * 1e18) / (_optimalUBorrow() + 1e18)
				)
			);
	}

	// TODO should we compute pending farm & lending rewards here?
	function getAndUpdateTVL() public returns (uint256 tvl) {
		(uint256 uBorrow, uint256 shortPosition) = _updateAndGetBorrowBalances();
		uint256 borrowBalance = _shortToUnderlying(shortPosition) + uBorrow;
		uint256 shortP = _short.balanceOf(address(this));
		uint256 shortBalance = shortP == 0
			? 0
			: _shortToUnderlying(_short.balanceOf(address(this)));
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 underlyingBalance = _underlying.balanceOf(address(this));
		tvl = underlyingLp * 2 - borrowBalance + underlyingBalance + shortBalance;
	}

	function getTotalTVL() public view returns (uint256 tvl) {
		(tvl, , , , , ) = getTVL();
	}

	/// THere is no situation where we would need this
	// function getOracleTvl() public returns (uint256 tvl) {
	// 	(uint256 underlyingBorrow, uint256 borrowPosition) = _updateAndGetBorrowBalances();
	// 	uint256 borrowBalance = _shortToUnderlyingOracle(borrowPosition) + underlyingBorrow;

	// 	uint256 shortPosition = _short.balanceOf(address(this));
	// 	uint256 shortBalance = shortPosition == 0 ? 0 : _shortToUnderlyingOracle(shortPosition);

	// 	(uint256 underlyingLp, uint256 shortLp) = _getLPBalances();
	// 	uint256 lpBalance = underlyingLp + _shortToUnderlyingOracle(shortLp);
	// 	uint256 underlyingBalance = _underlying.balanceOf(address(this));

	// 	tvl = lpBalance - borrowBalance + underlyingBalance + shortBalance;
	// }

	function getTVL()
		public
		view
		returns (
			uint256 tvl,
			uint256,
			uint256 borrowPosition,
			uint256 borrowBalance,
			uint256 lpBalance,
			uint256 underlyingBalance
		)
	{
		uint256 underlyingBorrow;
		(underlyingBorrow, borrowPosition) = _getBorrowBalances();
		borrowBalance = _shortToUnderlying(borrowPosition) + underlyingBorrow;

		uint256 shortPosition = _short.balanceOf(address(this));
		uint256 shortBalance = shortPosition == 0 ? 0 : _shortToUnderlying(shortPosition);

		(uint256 underlyingLp, uint256 shortLp) = _getLPBalances();
		lpBalance = underlyingLp + _shortToUnderlying(shortLp);
		underlyingBalance = _underlying.balanceOf(address(this));

		tvl = lpBalance - borrowBalance + underlyingBalance + shortBalance;
	}

	function getPositionOffset() public view returns (uint256 positionOffset) {
		(, uint256 shortLp) = _getLPBalances();
		(, uint256 borrowBalance) = _getBorrowBalances();
		uint256 shortBalance = shortLp + _short.balanceOf(address(this));
		if (shortBalance == borrowBalance) return 0;
		// if short lp > 0 and borrowBalance is 0 we are off by inf, returning 100% should be enough
		if (borrowBalance == 0) return 10000;
		// this is the % by which our position has moved from beeing balanced

		positionOffset = shortBalance > borrowBalance
			? ((shortBalance - borrowBalance) * BPS_ADJUST) / borrowBalance
			: ((borrowBalance - shortBalance) * BPS_ADJUST) / borrowBalance;
	}

	// UTILS
	function getExpectedPrice() external view returns (uint256) {
		return _shortToUnderlying(1e18);
	}

	function getLiquidity() external view returns (uint256) {
		return _getLiquidity();
	}

	// used to estimate price of collateral token in underlying
	function collateralToUnderlying() external view returns (uint256) {
		(uint256 uR, uint256 sR, ) = pair().getReserves();
		(uR, sR) = address(_underlying) == pair().token0() ? (uR, sR) : (sR, uR);
		uint256 lp = pair().totalSupply();
		// for deposit of 1 underlying we get 1+_optimalUBorrow worth or lp -> collateral token
		return (1e18 * (uR * _getLiquidity(1e18))) / lp / (1e18 + _optimalUBorrow());
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}

	error RebalanceThreshold();
	error LowLoanHealth();
	error SlippageExceeded();
	error OverMaxPriceOffset();
}
