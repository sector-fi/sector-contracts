// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { Auth } from "../../common/Auth.sol";
import { Fees } from "../../common/Fees.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { SCYStrategy, Strategy } from "./SCYStrategy.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

import "hardhat/console.sol";

abstract contract SCYVault is SCYStrategy, SCYBase, Fees {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 underlyingFees,
		uint256 sharesFees
	);

	address public strategy;

	// immutables
	address public immutable yieldToken;
	uint256 public immutable strategyId; // strategy-specific id ex: for MasterChef or 1155
	IERC20 public immutable underlying;

	uint96 public maxDust; // minimal amount of underlying token allowed before deposits are paused
	uint256 public maxTvl; // pack all params and balances
	uint256 public vaultTvl; // strategy balance in underlying
	uint256 public uBalance; // underlying balance held by vault

	event MaxDustUpdated(uint256 maxDust);
	event MaxTvlUpdated(uint256 maxTvl);
	event StrategyUpdated(address strategy);

	modifier isInitialized() {
		if (strategy == address(0)) revert NotInitialized();
		_;
	}

	constructor(
		address _owner,
		address _guardian,
		address _manager,
		Strategy memory _strategy
	)
		SCYBase(_strategy.name, _strategy.symbol)
		Auth(_owner, _guardian, _manager)
		Fees(_strategy.treasury, _strategy.performanceFee)
	{
		// strategy init
		yieldToken = _strategy.yieldToken;
		strategy = _strategy.addr;
		maxDust = _strategy.maxDust;
		strategyId = _strategy.strategyId;
		underlying = _strategy.underlying;
		maxTvl = _strategy.maxTvl;
	}

	/*///////////////////////////////////////////////////////////////
                    CONFIG
    //////////////////////////////////////////////////////////////*/

	function getMaxTvl() public view returns (uint256) {
		return min(maxTvl, _stratMaxTvl());
	}

	function setMaxTvl(uint256 _maxTvl) public onlyRole(GUARDIAN) {
		maxTvl = _maxTvl;
		emit MaxTvlUpdated(min(maxTvl, _stratMaxTvl()));
	}

	function setMaxDust(uint96 _maxDust) public onlyRole(GUARDIAN) {
		maxDust = _maxDust;
		emit MaxDustUpdated(_maxDust);
	}

	function initStrategy(address _strategy) public onlyRole(GUARDIAN) {
		if (strategy != address(0)) revert NoReInit();
		strategy = _strategy;
		_stratValidate();
		emit StrategyUpdated(_strategy);
	}

	function updateStrategy(address _strategy) public onlyOwner {
		uint256 tvl = _stratGetAndUpdateTvl();
		if (tvl > 0) revert InvalidStrategyUpdate();
		strategy = _strategy;
		_stratValidate();
		emit StrategyUpdated(_strategy);
	}

	function _deposit(
		address,
		address,
		uint256 amount
	) internal override isInitialized returns (uint256 sharesOut) {
		// if we have any float in the contract we cannot do deposit accounting
		if (isPaused()) revert DepositsPaused();
		uint256 yieldTokenAdded = _stratDeposit(amount);
		sharesOut = toSharesAfterDeposit(yieldTokenAdded);
		vaultTvl += amount;
	}

	function _redeem(
		address receiver,
		address,
		uint256 sharesToRedeem
	) internal override returns (uint256 amountTokenOut, uint256 amountToTransfer) {
		uint256 _totalAssets = totalAssets();

		uint256 yeildTokenRedeem = convertToAssets(sharesToRedeem);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		uint256 reserves = uBalance;
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalAssets;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) uBalance -= shareOfReserves;

		// if we also need to send the user share of reserves, we allways withdraw to vault first
		// if we don't we can have strategy withdraw directly to user if possible
		if (shareOfReserves > 0) {
			(amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenRedeem);
			amountTokenOut += shareOfReserves;
			amountToTransfer += shareOfReserves;
		} else (amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenRedeem);
		vaultTvl -= amountTokenOut;
	}

	// DoS attack is possible by depositing small amounts of underlying
	// can make it costly by using a maxDust amnt, ex: $100
	// TODO: make sure we don't need check
	function isPaused() public view returns (bool) {
		return uBalance > maxDust;
	}

	/// @notice Harvest a set of trusted strategies.
	/// @dev strategies param is for backwards compatibility.
	/// TODO slippage parameter to prevent sandwitch attack to inflate fees?
	function harvest(address[] calldata) external onlyRole(MANAGER) {
		uint256 tvl = _stratGetAndUpdateTvl() + underlying.balanceOf(address(this));
		uint256 prevTvl = vaultTvl;
		if (tvl <= prevTvl) return;

		uint256 underlyingEarned = tvl - prevTvl;
		uint256 underlyingFees = (underlyingEarned * performanceFee) / 1e18;
		uint256 feeShares = convertToShares(underlyingFees);

		_mint(treasury, feeShares);
		vaultTvl = tvl;
		emit Harvest(treasury, underlyingEarned, underlyingFees, feeShares);
	}

	/// @notice slippage is computed in shares
	function depositIntoStrategy(uint256 underlyingAmount, uint256 minAmountOut)
		public
		onlyRole(GUARDIAN)
	{
		if (underlyingAmount > uBalance) revert NotEnoughUnderlying();
		uBalance -= underlyingAmount;
		underlying.safeTransfer(strategy, underlyingAmount);
		uint256 yAdded = _stratDeposit(underlyingAmount);
		uint256 virtualSharesOut = toSharesAfterDeposit(yAdded);
		if (virtualSharesOut < minAmountOut) revert SlippageExceeded();
	}

	/// @notice slippage is computed in underlying
	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) public onlyRole(GUARDIAN) {
		uint256 yieldTokenAmnt = convertToAssets(shares);
		(uint256 underlyingWithdrawn, ) = _stratRedeem(address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
	}

	function closePosition(uint256 minAmountOut) public onlyRole(GUARDIAN) {
		uint256 underlyingWithdrawn = _stratClosePosition();
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
	}

	function getStrategyTvl() public view returns (uint256) {
		return _strategyTvl();
	}

	/// no slippage check - slippage can be done on vault level
	/// against total expected balance of all strategies
	function getAndUpdateTvl() public returns (uint256 tvl) {
		uint256 stratTvl = _stratGetAndUpdateTvl();
		uint256 balance = underlying.balanceOf(address(this));
		tvl = balance + stratTvl;
	}

	function getTvl() public view returns (uint256 tvl) {
		uint256 stratTvl = _strategyTvl();
		uint256 balance = underlying.balanceOf(address(this));
		tvl = balance + stratTvl;
	}

	// function _checkSlippage(
	// 	uint256 expectedRate,
	// 	uint256 actualRate,
	// 	uint256 maxDelta
	// ) internal pure {
	// 	uint256 delta = expectedRate > actualRate
	// 		? expectedRate - actualRate
	// 		: actualRate - expectedRate;
	// 	if (delta > maxDelta) revert SlippageExceeded();
	// }

	function totalAssets() public view override returns (uint256) {
		return _selfBalance(yieldToken);
	}

	// used for estimates only
	function exchangeRateUnderlying() public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return _stratCollateralToUnderlying();
		uint256 tvl = underlying.balanceOf(address(this)) + _strategyTvl();
		return tvl.mulDivUp(ONE, _totalSupply);
	}

	function underlyingBalance(address user) external view returns (uint256) {
		uint256 userBalance = balanceOf(user);
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0 || userBalance == 0) return 0;
		uint256 tvl = underlying.balanceOf(address(this)) + _strategyTvl();
		return (tvl * userBalance) / _totalSupply;
	}

	function underlyingToShares(uint256 uAmnt) public view returns (uint256) {
		return ((ONE * uAmnt) / exchangeRateUnderlying());
	}

	function sharesToUnderlying(uint256 shares) public view returns (uint256) {
		return (shares * exchangeRateUnderlying()) / ONE;
	}

	///
	///  Yield Token Overrides
	///

	function assetInfo()
		public
		view
		returns (
			AssetType assetType,
			address assetAddress,
			uint8 assetDecimals
		)
	{
		address yToken = yieldToken;
		return (AssetType.LIQUIDITY, yToken, IERC20Metadata(yToken).decimals());
	}

	function underlyingDecimals() public view returns (uint8) {
		return IERC20Metadata(address(underlying)).decimals();
	}

	function _getFloatingAmount(address token) internal view virtual override returns (uint256) {
		if (token == address(underlying)) return underlying.balanceOf(strategy);
		return _selfBalance(token);
	}

	function decimals() public view override returns (uint8) {
		return IERC20Metadata(yieldToken).decimals();
	}

	/**
	 * @dev See {ISuperComposableYield-exchangeRateCurrent}
	 */
	function exchangeRateCurrent() public view virtual override returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return ONE;
		return (_selfBalance(yieldToken) * ONE) / _totalSupply;
	}

	/**
	 * @dev See {ISuperComposableYield-exchangeRateStored}
	 */

	function exchangeRateStored() external view virtual override returns (uint256) {
		return exchangeRateCurrent();
	}

	function getBaseTokens() external view override returns (address[] memory res) {
		res[0] = address(underlying);
	}

	function isValidBaseToken(address token) public view override returns (bool) {
		return token == address(underlying);
	}

	// send funds to strategy
	function _transferIn(
		address token,
		address from,
		uint256 amount
	) internal virtual override {
		if (token == NATIVE) {
			// if strategy logic lives in this contract, don't do anything
			if (strategy == address(this)) return SafeETH.safeTransferETH(strategy, amount);
		} else IERC20(token).safeTransferFrom(from, strategy, amount);
	}

	// send funds to user
	function _transferOut(
		address token,
		address to,
		uint256 amount
	) internal virtual override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransferFrom(strategy, to, amount);
		}
	}

	// TODO handle internal float balances
	function _selfBalance(address token) internal view virtual override returns (uint256) {
		if (token == address(underlying)) return IERC20(token).balanceOf(address(this));
		return (token == NATIVE) ? strategy.balance : IERC20(token).balanceOf(strategy);
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}

	error InvalidStrategyUpdate();
	error NoReInit();
	error InvalidStrategy();
	error NotInitialized();
	error DepositsPaused();
	error StrategyExists();
	error StrategyDoesntExist();
	error NotEnoughUnderlying();
	error SlippageExceeded();
	error BadStaticCall();
}
