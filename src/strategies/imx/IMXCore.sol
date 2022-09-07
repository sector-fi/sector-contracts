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

	uint256 constant MINIMUM_LIQUIDITY = 1000;
	uint256 constant BPS_ADJUST = 10000;

	IERC20 private _underlying;
	IERC20 private _short;

	uint256 private _maxTvl;
	uint16 public rebalanceThreshold = 400; // 4% of lp
	// price move before liquidation
	uint256 private _safetyMarginSqrt = 1.118033989e18; // sqrt of 125%

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

		_safetyMarginSqrt = 1.118033989e18;
		emit SetSafetyMarginSqrt(_safetyMarginSqrt);
	}

	function safetyMarginSqrt() internal view override returns (uint256) {
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

	// TODO deleverage method?
	// public method that anyone can call to prevent an immenent loan liquidation
	// this is an emergency measure in case rebalance() is not called in time
	// price check is not necessary here because we are only removing LP and
	// if swap price differs it is to our benefit
	// function rebalanceLoan() public nonReentrant {
	// }

	// deposit underlying and recieve lp tokens
	function deposit(uint256 underlyingAmnt) external onlyVault nonReentrant {
		if (underlyingAmnt <= 0) return; // cannot deposit 0
		uint256 tvl = getAndUpdateTVL();
		require(underlyingAmnt + tvl <= getMaxTvl(), "STRAT: OVER_MAX_TVL");

		// if we have any un-allocated underlying,
		// it means we are over capacity or in a paused state
		// TODO: ensure this doesn't fail because of dust
		require(_underlying.balanceOf(address(this)) <= underlyingAmnt, "STRAT: OVER CAPACITY");

		_increasePosition(underlyingAmnt);
	}

	// redeem lp for underlying
	function redeem(uint256 lpAmnt) public onlyVault returns (uint256 amountTokenOut) {
		// this is the full amount of LP tokens totalSupply of shares is entitled to
		uint256 lpBalance = _getLiquidity();
		_decreasePosition(lpBalance, lpAmnt);

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
	function _decreasePosition(uint256 lpBalance, uint256 removeLp) internal {
		(uint256 uBorrowBalance, uint256 sBorrowBalance) = _updateAndGetBorrowBalances();

		// remove lp & repay underlying loan
		uint256 uRepay = (uBorrowBalance * removeLp) / lpBalance;
		uint256 sRepay = removeLp == lpBalance ? sBorrowBalance : type(uint256).max;

		_removeIMXLiquidity(removeLp, uRepay, sRepay);

		// this method may fail if withdrawal brings the position out of balance or close to liquidation
		// this can happen if a large portion of the balance is being removed from an already un-balanced position
		// TODO can limit this check to liquidation threshold?
		require(getPositionOffset() <= rebalanceThreshold, "STRAT: OUT_OF_BALANCE");
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

	// TODO: add slippage param
	function increasePosition(uint256 amount) external nonReentrant onlyRole(GUARDIAN) {
		require(_underlying.balanceOf(address(this)) >= amount, "STRAT: NOT ENOUGH U");
		_increasePosition(amount);
	}

	// TODO: add slippage param
	function decreasePosition(uint256 lp) external nonReentrant onlyRole(GUARDIAN) {
		uint256 lpBalance = _getLiquidity();
		_decreasePosition(lpBalance, lp);
	}

	// use prev harvest interface?
	// function harvest(
	// 	HarvestSwapParms[] calldata uniParams,
	// 	HarvestSwapParms[] calldata lendingParams
	// ) external onlyRole(MANAGER) nonReentrant {}

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

	// TODO: add slippage
	function rebalance() external onlyRole(MANAGER) nonReentrant {
		// call this first to ensure we use an updated borrowBalance when computing offset
		uint256 tvl = getAndUpdateTVL();
		uint256 positionOffset = getPositionOffset();

		// don't rebalance unless we exceeded the threshold
		require(positionOffset > rebalanceThreshold, "HLP: REB-THRESH"); // maybe next time...

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
			uint256 removeLp = _getLiquidity() -
				(_getLiquidity() * targetUnderlyingLP) /
				underlyingLp;
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

	// TODO add slippage
	// TODO partial close / deleverage?
	function closePosition() public onlyVault {
		(uint256 uRepay, uint256 sRepay) = _updateAndGetBorrowBalances();
		_removeIMXLiquidity(_getLiquidity(), uRepay, sRepay);
		// transfer funds to vault
		_underlying.safeTransfer(vault, _underlying.balanceOf(address(this)));
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

	function getTVL()
		public
		view
		returns (
			uint256 tvl,
			uint256 collateralBalance,
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

		tvl = collateralBalance + lpBalance - borrowBalance + underlyingBalance + shortBalance;
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

	function getLiquidity() external view returns (uint256) {
		return _getLiquidity();
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
}
