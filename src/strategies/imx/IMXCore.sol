// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { IBase, HarvestSwapParams } from "../mixins/IBase.sol";
import { IIMXFarm } from "../mixins/IIMXFarm.sol";
import { UniUtils, IUniswapV2Pair } from "../../libraries/UniUtils.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

import { StratAuth } from "../../common/StratAuth.sol";

// import "hardhat/console.sol";

abstract contract IMXCore is ReentrancyGuard, StratAuth, IBase, IIMXFarm {
	using FixedPointMathLib for uint256;
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

	constructor(
		address vault_,
		address underlying_,
		address short_,
		uint256 maxTvl_
	) {
		vault = vault_;
		_underlying = IERC20(underlying_);
		_short = IERC20(short_);

		// _underlying.safeApprove(vault, type(uint256).max);

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
		require(rebalanceThreshold_ >= 100, "HLP: BAD_INPUT");
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
		// deposit is already included in tvl
		uint256 tvl = getAndUpdateTVL();
		require(tvl <= getMaxTvl(), "STRAT: OVER_MAX_TVL");
		uint256 startBalance = collateralToken().balanceOf(address(this));
		_increasePosition(underlyingAmnt);
		uint256 endBalance = collateralToken().balanceOf(address(this));
		return endBalance - startBalance;
	}

	// redeem lp for underlying
	function redeem(uint256 removeCollateral, address recipient)
		public
		onlyVault
		returns (uint256 amountTokenOut)
	{
		// this is the full amount of LP tokens totalSupply of shares is entitled to
		_decreasePosition(removeCollateral);

		// TODO make sure we never have any extra underlying dust sitting around
		// all 'extra' underlying should allways be transferred back to the vault

		unchecked {
			amountTokenOut = _underlying.balanceOf(address(this));
		}
		_underlying.safeTransfer(recipient, amountTokenOut);
		emit Redeem(msg.sender, amountTokenOut);
	}

	/// @notice decreases position based to desired LP amount
	/// @dev ** does not rebalance remaining portfolio
	/// @param removeCollateral amount of callateral token to remove
	function _decreasePosition(uint256 removeCollateral) internal {
		(uint256 uBorrowBalance, uint256 sBorrowBalance) = _updateAndGetBorrowBalances();

		uint256 balance = collateralToken().balanceOf(address(this));
		uint256 lp = _getLiquidity(balance);

		// remove lp & repay underlying loan
		// round up to avoid under-repaying
		uint256 removeLp = lp.mulDivUp(removeCollateral, balance);
		uint256 uRepay = uBorrowBalance.mulDivUp(removeCollateral, balance);
		uint256 sRepay = sBorrowBalance.mulDivUp(removeCollateral, balance);

		_removeIMXLiquidity(removeLp, uRepay, sRepay);
	}

	// increases the position based on current desired balance
	// ** does not rebalance remaining portfolio
	function _increasePosition(uint256 amntUnderlying) internal {
		if (amntUnderlying < MINIMUM_LIQUIDITY) return; // avoid imprecision
		(uint256 uLp, ) = _getLPBalances();
		(uint256 uBorrowBalance, uint256 sBorrowBalance) = _getBorrowBalances();

		uint256 tvl = getAndUpdateTVL() - amntUnderlying;

		uint256 uBorrow;
		uint256 sBorrow;
		uint256 aUddLp;
		uint256 sAddLp;

		if (tvl == 0) {
			uBorrow = (_optimalUBorrow() * amntUnderlying) / 1e18;
			aUddLp = amntUnderlying + uBorrow;
			sBorrow = _underlyingToShort(aUddLp);
			sAddLp = sBorrow;
		} else {
			// if tvl > 0 we need to keep the exact proportions of current position
			// to ensure we have correct accounting independent of price moves
			uBorrow = (uBorrowBalance * amntUnderlying) / tvl;
			aUddLp = (uLp * amntUnderlying) / tvl;
			sBorrow = (sBorrowBalance * amntUnderlying) / tvl;
			sAddLp = _underlyingToShort(aUddLp);
		}

		_addIMXLiquidity(aUddLp, sAddLp, uBorrow, sBorrow);
	}

	// use the return of the function to estimate pending harvest via staticCall
	function harvest(HarvestSwapParams[] calldata harvestParams)
		external
		onlyVault
		nonReentrant
		returns (uint256[] memory farmHarvest)
	{
		(uint256 startTvl, , , , , ) = getTVL();

		farmHarvest = new uint256[](1);
		farmHarvest[0] = _harvestFarm(harvestParams[0]);

		// compound our lp position
		_increasePosition(_underlying.balanceOf(address(this)));
		emit Harvest(startTvl);
	}

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
		// GUARDIAN can execute rebalance any time
		if (positionOffset <= rebalanceThreshold && !hasRole(GUARDIAN, msg.sender))
			revert RebalanceThreshold();

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
		tvl = underlyingLp * 2 + underlyingBalance + shortBalance - borrowBalance;
	}

	function getTotalTVL() public view returns (uint256 tvl) {
		(tvl, , , , , ) = getTVL();
	}

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

	function getLPBalances() public view returns (uint256 underlyingLp, uint256 shortLp) {
		return _getLPBalances();
	}

	function getLiquidity() external view returns (uint256) {
		return _getLiquidity();
	}

	// used to estimate price of collateral token in underlying
	function collateralToUnderlying() external view returns (uint256) {
		(uint256 uR, uint256 sR, ) = pair().getReserves();
		(uR, sR) = address(_underlying) == pair().token0() ? (uR, sR) : (sR, uR);
		uint256 lp = pair().totalSupply();
		// for deposit of 1 underlying we get 1+_optimalUBorrow worth of lp -> collateral token
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
