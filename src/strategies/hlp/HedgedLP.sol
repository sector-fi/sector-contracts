// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../mixins/IBase.sol";
import "../mixins/ILending.sol";
import "../mixins/IUniLp.sol";
import "./BaseStrategy.sol";
import "../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

// @custom: alphabetize dependencies to avoid linearization conflicts
abstract contract HedgedLP is IBase, BaseStrategy, ILending, IUniFarm {
	using UniUtils for IUniswapV2Pair;
	using SafeERC20 for IERC20;

	event RebalanceLoan(address indexed sender, uint256 startLoanHealth, uint256 updatedLoanHealth);
	event setMinLoanHealth(uint256 loanHealth);
	event SetMaxDefaultPriceMismatch(uint256 maxDefaultPriceMismatch);
	event SetRebalanceThreshold(uint256 rebalanceThreshold);
	event SetMaxTvl(uint256 maxTvl);
	event SetSafeCollateralRaio(uint256 collateralRatio);

	uint256 constant MIN_LIQUIDITY = 1000;
	uint256 public constant maxPriceOffset = 2000; // maximum offset for rebalanceLoan & manager  methods 20%

	IERC20 private _underlying;
	IERC20 private _short;

	uint256 public maxDefaultPriceMismatch = 100; // 1%
	uint256 public constant maxAllowedMismatch = 300; // manager cannot set user-price mismatch to more than 3%
	uint256 public minLoanHealth = 1.15e18; // how close to liquidation we get

	uint16 public rebalanceThreshold = 400; // 4% of lp

	uint256 private _maxTvl;
	uint256 private _safeCollateralRatio = 8000; // 80%

	uint256 public constant version = 1;

	modifier checkPrice(uint256 maxSlippage) {
		if (maxSlippage == 0)
			maxSlippage = maxDefaultPriceMismatch;
			// manager accounts cannot set maxSlippage bigger than maxPriceOffset
		else require(maxSlippage <= maxPriceOffset || isGuardian(msg.sender), "HLP: MAX_MISMATCH");
		require(getPriceOffset() <= maxSlippage, "HLP: PRICE_MISMATCH");
		_;
	}

	function __HedgedLP_init_(
		address underlying_,
		address short_,
		uint256 maxTvl_
	) internal initializer {
		_underlying = IERC20(underlying_);
		_short = IERC20(short_);

		_underlying.safeApprove(address(this), type(uint256).max);

		BASE_UNIT = 10**decimals();

		// init params
		setMaxTvl(maxTvl_);

		// emit default settings events
		emit setMinLoanHealth(minLoanHealth);
		emit SetMaxDefaultPriceMismatch(maxDefaultPriceMismatch);
		emit SetRebalanceThreshold(rebalanceThreshold);
		emit SetSafeCollateralRaio(_safeCollateralRatio);

		// TODO should we add a revoke aprovals methods?
		_addLendingApprovals();
		_addFarmApprovals();

		isInitialized = true;
	}

	function safeCollateralRatio() public view override returns (uint256) {
		return _safeCollateralRatio;
	}

	function setSafeCollateralRatio(uint256 safeCollateralRatio_) public onlyOwner {
		require(safeCollateralRatio_ >= 1000 && safeCollateralRatio_ <= 8500, "HLP: BAD_INPUT");
		_safeCollateralRatio = safeCollateralRatio_;
		emit SetSafeCollateralRaio(safeCollateralRatio_);
	}

	function decimals() public view returns (uint8) {
		return IERC20Metadata(address(_underlying)).decimals();
	}

	// OWNER CONFIG
	function setMinLoanHeath(uint256 minLoanHealth_) public onlyOwner {
		require(minLoanHealth_ > 1e18, "HLP: BAD_INPUT");
		minLoanHealth = minLoanHealth_;
		emit setMinLoanHealth(minLoanHealth_);
	}

	// guardian can adjust max default price mismatch if needed
	function setMaxDefaultPriceMismatch(uint256 maxDefaultPriceMismatch_) public onlyGuardian {
		require(maxDefaultPriceMismatch_ >= 25, "HLP: BAD_INPUT"); // no less than .25%
		require(
			msg.sender == owner() || maxAllowedMismatch >= maxDefaultPriceMismatch_,
			"HLP: BAD_INPUT"
		);
		maxDefaultPriceMismatch = maxDefaultPriceMismatch_;
		emit SetMaxDefaultPriceMismatch(maxDefaultPriceMismatch_);
	}

	function setRebalanceThreshold(uint16 rebalanceThreshold_) public onlyOwner {
		// rebalance threshold should not be lower than 1% (2% price move)
		require(rebalanceThreshold_ >= 100, "HLP: BAD_INPUT");
		rebalanceThreshold = rebalanceThreshold_;
		emit SetRebalanceThreshold(rebalanceThreshold_);
	}

	function setMaxTvl(uint256 maxTvl_) public onlyGuardian {
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

	// public method that anyone can call if loan health falls below minLoanHealth
	// this method will succeed only when loanHealth is below minimum
	function rebalanceLoan() public nonReentrant {
		// limit offset to maxPriceOffset manager to prevent misuse
		if (isGuardian(msg.sender)) {} else if (isManager(msg.sender))
			require(getPriceOffset() <= maxPriceOffset, "HLP: MAX_MISMATCH");
			// public methods need more protection agains griefing
			// NOTE: this may prevent gelato bots from executing the tx in the case of
			// a sudden price spike on a CEX
		else require(getPriceOffset() <= maxDefaultPriceMismatch, "HLP: PRICE_MISMATCH");

		uint256 _loanHealth = loanHealth();
		require(_loanHealth <= minLoanHealth, "HLP: SAFE");
		_rebalanceLoan(_loanHealth);
	}

	function _rebalanceLoan(uint256 _loanHealth) internal {
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 collateral = _getCollateralBalance();

		// get back to our target _safeCollateralRatio
		uint256 targetHealth = (10000 * 1e18) / _safeCollateralRatio;
		uint256 addCollateral = (1e18 * ((collateral * targetHealth) / _loanHealth - collateral)) /
			((targetHealth * 1e18) / _getCollateralFactor() + 1e18);

		// remove lp
		(uint256 underlyingBalance, uint256 shortBalance) = _decreaseLpTo(
			underlyingLp - addCollateral
		);

		_repay(shortBalance);
		_lend(underlyingBalance);
		emit RebalanceLoan(msg.sender, _loanHealth, loanHealth());
	}

	function _deposit(uint256 amount)
		internal
		override
		checkPrice(0)
		nonReentrant
		returns (uint256 newShares)
	{
		if (amount <= 0) return 0; // cannot deposit 0
		uint256 tvl = _getAndUpdateTVL();
		require(amount + tvl <= getMaxTvl(), "HLP: OVER_MAX_TVL");
		newShares = totalSupply() == 0 ? amount : (totalSupply() * amount) / tvl;
		_underlying.safeTransferFrom(vault(), address(this), amount);
		_increasePosition(amount);
	}

	function _withdraw(uint256 amount)
		internal
		override
		checkPrice(0)
		nonReentrant
		returns (uint256 burnShares)
	{
		if (amount == 0) return 0;
		uint256 tvl = _getAndUpdateTVL();
		if (tvl == 0) return 0;

		uint256 reserves = _underlying.balanceOf(address(this));

		// if we can not withdraw straight out of reserves
		if (amount > reserves) {
			// decrease current position
			reserves = _decreasePosition(amount - reserves, reserves, tvl);

			// use the minimum of underlying balance and requested amount
			amount = min(reserves, amount);
		}

		// grab current tvl to account for fees and slippage
		(tvl, , , , , ) = getTVL();

		// round up to keep price precision and leave less dust
		burnShares = min(((amount + 1) * totalSupply()) / tvl, totalSupply());

		_underlying.safeTransferFrom(address(this), vault(), amount);
	}

	// decreases position based on current desired balance
	// ** does not rebalance remaining portfolio
	// ** may return slighly less than desired amount
	// ** make sure to update lending positions before calling this
	// we use the inflated amntWithBuffer to withdraw lp
	// and the smaller withdrawAmnt to withdraw collateral, so that we
	// err on the side of adding more collateral
	function _decreasePosition(
		uint256 withdrawAmnt,
		uint256 reserves,
		uint256 tvl
	) internal returns (uint256) {
		// add .5% to withdraw to boost collateral just in case its low
		uint256 amntWithBuffer = (withdrawAmnt * 1005) / 1000;

		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 removeLpAmnt = (amntWithBuffer * underlyingLp) / (tvl);

		uint256 shortPosition = _getBorrowBalance();
		uint256 removeShortLp = _underlyingToShort(removeLpAmnt);

		if (removeLpAmnt >= underlyingLp || removeShortLp >= shortPosition) return _closePosition();

		// remove lp
		(uint256 availableUnderlying, uint256 shortBalance) = _decreaseLpTo(
			underlyingLp - removeLpAmnt
		);

		_repay(shortBalance);

		// this might remove less collateral than desired if we hit the loan health limit
		// this can happen when we are close to closing the position
		if (withdrawAmnt > availableUnderlying)
			availableUnderlying += _removeCollateral(withdrawAmnt - availableUnderlying);

		// ensure we don't fall below loan health limit (this should not normally happen)
		uint256 _loanHealth = loanHealth();
		if (_loanHealth <= minLoanHealth) _rebalanceLoan(_loanHealth);
		return availableUnderlying + reserves;
	}

	// increases the position based on current desired balance
	// ** does not rebalance remaining portfolio
	function _increasePosition(uint256 amount) internal {
		if (amount < MIN_LIQUIDITY) return; // avoid imprecision
		uint256 amntUnderlying = _totalToLp(amount);
		uint256 amntShort = _underlyingToShort(amntUnderlying);
		_lend(amount - amntUnderlying);
		_borrow(amntShort);
		uint256 liquidity = _addLiquidity(amntUnderlying, amntShort);
		_depositIntoFarm(liquidity);
	}

	// use the return of the function to estimate pending harvest via staticCall
	function harvest(
		HarvestSwapParms[] calldata uniParams,
		HarvestSwapParms[] calldata lendingParams
	)
		external
		onlyManager
		checkPrice(0)
		nonReentrant
		returns (uint256[] memory farmHarvest, uint256[] memory lendHarvest)
	{
		(uint256 startTvl, , , , , ) = getTVL();
		if (uniParams.length != 0) farmHarvest = _harvestFarm(uniParams);
		if (lendingParams.length != 0) lendHarvest = _harvestLending(lendingParams);

		// compound our lp position
		_increasePosition(underlying().balanceOf(address(this)));
		emit Harvest(startTvl);
	}

	function rebalance(uint256 maxSlippage)
		external
		onlyManager
		checkPrice(maxSlippage)
		nonReentrant
	{
		// call this first to ensure we use an updated borrowBalance when computing offset
		uint256 tvl = _getAndUpdateTVL();
		uint256 positionOffset = getPositionOffset();

		// don't rebalance unless we exceeded the threshold
		require(positionOffset > rebalanceThreshold, "HLP: REB-THRESH"); // maybe next time...

		if (tvl == 0) return;
		uint256 targetUnderlyingLP = _totalToLp(tvl);

		// add .1% room for fees
		_rebalancePosition((targetUnderlyingLP * 999) / 1000, tvl - targetUnderlyingLP);
		emit Rebalance(_shortToUnderlying(1e18), positionOffset, tvl);
	}

	// note: one should call harvest immediately before close position
	function closePosition(uint256 maxSlippage) public checkPrice(maxSlippage) onlyGuardian {
		_closePosition();
		emit UpdatePosition();
	}

	// in case of emergency - remove LP
	function removeLiquidity(uint256 removeLp, uint256 maxSlippage)
		public
		checkPrice(maxSlippage)
		onlyGuardian
	{
		_removeLiquidity(removeLp);
		emit UpdatePosition();
	}

	// in case of emergency - withdraw lp tokens from farm
	function withdrawFromFarm() public onlyGuardian {
		_withdrawFromFarm(_getFarmLp());
		emit UpdatePosition();
	}

	// in case of emergency - withdraw stuck collateral
	function redeemCollateral(uint256 repayAmnt, uint256 withdrawAmnt) public onlyGuardian {
		_repay(repayAmnt);
		_redeem(withdrawAmnt);
		emit UpdatePosition();
	}

	function _closePosition() internal returns (uint256) {
		_decreaseLpTo(0);
		uint256 shortPosition = _updateAndGetBorrowBalance();
		uint256 shortBalance = _short.balanceOf(address(this));
		if (shortPosition > shortBalance) {
			pair()._swapTokensForExactTokens(
				shortPosition - shortBalance,
				address(_underlying),
				address(_short)
			);
		} else if (shortBalance > shortPosition) {
			pair()._swapExactTokensForTokens(
				shortBalance - shortPosition,
				address(_short),
				address(_underlying)
			);
		}
		_repay(_short.balanceOf(address(this)));
		uint256 collateralBalance = _updateAndGetCollateralBalance();
		_redeem(collateralBalance);
		return _underlying.balanceOf(address(this));
	}

	function _decreaseLpTo(uint256 targetUnderlyingLP)
		internal
		returns (uint256 underlyingRemove, uint256 shortRemove)
	{
		(uint256 underlyingLp, ) = _getLPBalances();
		if (targetUnderlyingLP >= underlyingLp) return (0, 0); // nothing to withdraw
		uint256 liquidity = _getLiquidity();
		uint256 targetLiquidity = (liquidity * targetUnderlyingLP) / underlyingLp;
		uint256 removeLp = liquidity - targetLiquidity;
		uint256 liquidityBalance = pair().balanceOf(address(this));
		if (removeLp > liquidityBalance) _withdrawFromFarm(removeLp - liquidityBalance);
		return removeLp == 0 ? (0, 0) : _removeLiquidity(removeLp);
	}

	function _rebalancePosition(uint256 targetUnderlyingLP, uint256 targetCollateral) internal {
		uint256 targetBorrow = _underlyingToShort(targetUnderlyingLP);
		// we already updated tvl
		uint256 currentBorrow = _getBorrowBalance();

		// borrow funds or repay loan
		if (targetBorrow > currentBorrow) {
			// remove extra lp (we may need to remove more in order to add more collateral)
			_decreaseLpTo(
				_needUnderlying(targetUnderlyingLP, targetCollateral) > 0 ? 0 : targetUnderlyingLP
			);
			// add collateral
			_adjustCollateral(targetCollateral);
			_borrow(targetBorrow - currentBorrow);
		} else if (targetBorrow < currentBorrow) {
			// remove all of lp so we can repay loan
			_decreaseLpTo(0);
			uint256 repayAmnt = min(_short.balanceOf(address(this)), currentBorrow - targetBorrow);
			if (repayAmnt > 0) _repay(repayAmnt);
			// remove extra collateral
			_adjustCollateral(targetCollateral);
		}
		_increaseLpPosition(targetBorrow);
	}

	///////////////////////////
	//// INCREASE LP POSITION
	///////////////////////
	function _increaseLpPosition(uint256 targetBorrow) internal {
		uint256 underlyingBalance = _underlying.balanceOf(address(this));
		uint256 shortBalance = _short.balanceOf(address(this));

		// here we make sure we don't add extra lp
		(, uint256 shortLP) = _getLPBalances();

		if (targetBorrow < shortLP) return;

		uint256 addShort = min(
			(shortBalance + _underlyingToShort(underlyingBalance)) / 2,
			targetBorrow - shortLP
		);

		uint256 addUnderlying = _shortToUnderlying(addShort);

		// buy or sell underlying
		if (addUnderlying < underlyingBalance) {
			shortBalance += pair()._swapExactTokensForTokens(
				underlyingBalance - addUnderlying,
				address(_underlying),
				address(_short)
			);
			underlyingBalance = addUnderlying;
		} else if (shortBalance > addShort) {
			// swap extra tokens back (this may end up using more gas)
			underlyingBalance += pair()._swapExactTokensForTokens(
				shortBalance - addShort,
				address(_short),
				address(_underlying)
			);
			shortBalance = addShort;
		}

		// compute final lp amounts
		uint256 amntShort = shortBalance;
		uint256 amntUnderlying = _shortToUnderlying(amntShort);
		if (underlyingBalance < amntUnderlying) {
			amntUnderlying = underlyingBalance;
			amntShort = _underlyingToShort(amntUnderlying);
		}

		if (amntUnderlying == 0) return;

		// add liquidity
		// don't need to use min with underlying and short because we did oracle check
		// amounts are exact because we used swap price above
		uint256 liquidity = _addLiquidity(amntUnderlying, amntShort);
		_depositIntoFarm(liquidity);
	}

	function _needUnderlying(uint256 tragetUnderlying, uint256 targetCollateral)
		internal
		view
		returns (uint256)
	{
		uint256 collateralBalance = _getCollateralBalance();
		if (targetCollateral < collateralBalance) return 0;
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 uBalance = tragetUnderlying > underlyingLp ? tragetUnderlying - underlyingLp : 0;
		uint256 addCollateral = targetCollateral - collateralBalance;
		if (uBalance >= addCollateral) return 0;
		return addCollateral - uBalance;
	}

	// TVL

	function getMaxTvl() public view override returns (uint256) {
		// we don't want to get precise max borrow amaount available,
		// we want to stay at least a getCollateralRatio away from max borrow
		return min(_maxTvl, _oraclePriceOfShort(_maxBorrow() + _getBorrowBalance()));
	}

	// TODO should we compute pending farm & lending rewards here?
	function _getAndUpdateTVL() internal returns (uint256 tvl) {
		uint256 collateralBalance = _updateAndGetCollateralBalance();
		uint256 shortPosition = _updateAndGetBorrowBalance();
		uint256 borrowBalance = _shortToUnderlying(shortPosition);
		uint256 shortP = _short.balanceOf(address(this));
		uint256 shortBalance = shortP == 0 ? 0 : _shortToUnderlying(shortP);
		(uint256 underlyingLp, ) = _getLPBalances();
		uint256 underlyingBalance = _underlying.balanceOf(address(this));
		tvl =
			collateralBalance +
			underlyingLp *
			2 -
			borrowBalance +
			underlyingBalance +
			shortBalance;
	}

	// We can include a checkPrice(0) here for extra security
	// but it's not necessary with latestvault updates
	function balanceOfUnderlying() public view override returns (uint256 assets) {
		(assets, , , , , ) = getTVL();
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
		collateralBalance = _getCollateralBalance();
		borrowPosition = _getBorrowBalance();
		borrowBalance = _shortToUnderlying(borrowPosition);

		uint256 shortPosition = _short.balanceOf(address(this));
		uint256 shortBalance = shortPosition == 0 ? 0 : _shortToUnderlying(shortPosition);

		(uint256 underlyingLp, uint256 shortLp) = _getLPBalances();
		lpBalance = underlyingLp + _shortToUnderlying(shortLp);

		underlyingBalance = _underlying.balanceOf(address(this));

		tvl = collateralBalance + lpBalance - borrowBalance + underlyingBalance + shortBalance;
	}

	function getLPBalances() public view returns (uint256 underlyingLp, uint256 shortLp) {
		return _getLPBalances();
	}

	function getLiquidity() public view returns (uint256) {
		return _getLiquidity();
	}

	function getPositionOffset() public view returns (uint256 positionOffset) {
		(, uint256 shortLp) = _getLPBalances();
		uint256 borrowBalance = _getBorrowBalance();
		uint256 shortBalance = shortLp + _short.balanceOf(address(this));

		if (shortBalance == borrowBalance) return 0;
		// if short lp > 0 and borrowBalance is 0 we are off by inf, returning 100% should be enough
		if (borrowBalance == 0) return 10000;

		// this is the % by which our position has moved from beeing balanced
		positionOffset = shortBalance > borrowBalance
			? ((shortBalance - borrowBalance) * BPS_ADJUST) / borrowBalance
			: ((borrowBalance - shortBalance) * BPS_ADJUST) / borrowBalance;
	}

	function getPriceOffset() public view returns (uint256 offset) {
		uint256 minPrice = _shortToUnderlying(1e18);
		uint256 maxPrice = _oraclePriceOfShort(1e18);
		(minPrice, maxPrice) = maxPrice > minPrice ? (minPrice, maxPrice) : (maxPrice, minPrice);
		offset = ((maxPrice - minPrice) * BPS_ADJUST) / maxPrice;
	}

	// UTILS

	function _totalToLp(uint256 total) internal view returns (uint256) {
		uint256 cRatio = getCollateralRatio();
		return (total * cRatio) / (BPS_ADJUST + cRatio);
	}

	// this is the current uniswap price
	function _shortToUnderlying(uint256 amount) internal view returns (uint256) {
		return amount == 0 ? 0 : _quote(amount, address(_short), address(_underlying));
	}

	// this is the current uniswap price
	function _underlyingToShort(uint256 amount) internal view returns (uint256) {
		return amount == 0 ? 0 : _quote(amount, address(_underlying), address(_short));
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
}
