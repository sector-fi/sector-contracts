// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { Auth } from "../../common/Auth.sol";
import { Fees } from "../../common/Fees.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { SCYStrategy, Strategy } from "./SCYStrategy.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

abstract contract SCYVault is SCYStrategy, SCYBase, Fees {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 performanceFee,
		uint256 managementFee,
		uint256 sharesFees,
		uint256 tvl
	);

	uint256 public lastHarvestTimestamp;
	uint256 public lastHarvestInterval; // time interval of last harvest
	uint256 public maxLockedProfit;

	address payable public strategy;

	// immutables
	address public immutable yieldToken;
	uint256 public immutable strategyId; // strategy-specific id ex: for MasterChef or 1155
	IERC20 public immutable underlying;

	uint256 public maxTvl; // pack all params and balances
	uint256 public vaultTvl; // strategy balance in underlying
	uint256 public uBalance; // underlying balance held by vault

	event MaxTvlUpdated(uint256 maxTvl);
	event StrategyUpdated(address strategy);

	modifier isInitialized() {
		if (strategy == address(0)) revert NotInitialized();
		_;
	}

	constructor(Strategy memory _strategy) SCYBase(_strategy.name, _strategy.symbol) {
		// strategy init
		yieldToken = _strategy.yieldToken;
		strategy = payable(_strategy.addr);
		strategyId = _strategy.strategyId;
		underlying = _strategy.underlying;
		maxTvl = _strategy.maxTvl;

		lastHarvestTimestamp = block.timestamp;
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

	function initStrategy(address _strategy) public onlyRole(GUARDIAN) {
		if (strategy != address(0)) revert NoReInit();
		strategy = payable(_strategy);
		_stratValidate();
		emit StrategyUpdated(_strategy);
	}

	function updateStrategy(address _strategy) public onlyOwner {
		uint256 tvl = _stratGetAndUpdateTvl();
		if (tvl > 0) revert InvalidStrategyUpdate();
		strategy = payable(_strategy);
		_stratValidate();
		emit StrategyUpdated(_strategy);
	}

	function _depositNative() internal override {
		uint256 balance = address(this).balance;
		IWETH(address(underlying)).deposit{ value: balance }();
		if (sendERC20ToStrategy) IERC20(underlying).safeTransfer(strategy, balance);
	}

	function _deposit(
		address,
		address token,
		uint256 amount
	) internal override isInitialized returns (uint256 sharesOut) {
		// if we have any float in the contract we cannot do deposit accounting
		if (uBalance > 0) revert DepositsPaused();
		if (token == NATIVE) _depositNative();
		if (!sendERC20ToStrategy) underlying.safeTransfer(strategy, amount);
		uint256 yieldTokenAdded = _stratDeposit(amount);
		sharesOut = toSharesAfterDeposit(yieldTokenAdded);
		vaultTvl += amount;
	}

	function _redeem(
		address receiver,
		address token,
		uint256 sharesToRedeem
	) internal override returns (uint256 amountTokenOut, uint256 amountToTransfer) {
		uint256 _totalSupply = totalSupply();

		// adjust share amount for lockedProfit
		// we still burn the full sharesToRedeem, but fewer assets are returned
		// this is required in order to prevent harvest front-running
		sharesToRedeem = (sharesToRedeem * (_totalSupply - lockedProfit())) / _totalSupply;
		uint256 yeildTokenRedeem = convertToAssets(sharesToRedeem);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		// TODO why not use underlying.balanceOf?
		uint256 reserves = uBalance;
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalSupply;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) uBalance -= shareOfReserves;

		receiver = token == NATIVE ? address(this) : receiver;

		// if we also need to send the user share of reserves, we allways withdraw to vault first
		// if we don't we can have strategy withdraw directly to user if possible
		if (shareOfReserves > 0) {
			(amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenRedeem);
			amountTokenOut += shareOfReserves;
			amountToTransfer += shareOfReserves;
		} else (amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenRedeem);
		vaultTvl -= amountTokenOut;

		// it requested token is native, convert to native
		if (token == NATIVE) IWETH(address(underlying)).withdraw(amountToTransfer);
	}

	/// @notice harvest strategy
	function harvest(uint256 expectedTvl, uint256 maxDelta) external onlyRole(MANAGER) {
		uint256 tvl = _stratGetAndUpdateTvl() + underlying.balanceOf(address(this));
		_checkSlippage(expectedTvl, tvl, maxDelta);
		uint256 prevTvl = vaultTvl;
		uint256 timestamp = block.timestamp;
		uint256 profit = tvl > prevTvl ? tvl - prevTvl : 0;

		// PROCESS VAULT FEES
		uint256 _performanceFee = profit == 0 ? 0 : (profit * performanceFee) / 1e18;
		uint256 _managementFee = managementFee == 0
			? 0
			: (managementFee * tvl * (timestamp - lastHarvestTimestamp)) / 1e18 / 365 days;

		uint256 totalFees = _performanceFee + _managementFee;
		uint256 feeShares;
		if (totalFees > 0) {
			// we know that totalSupply != 0 and tvl > totalFees
			// this results in more accurate accounting considering dilution
			feeShares = totalFees.mulDivDown(totalSupply(), tvl - totalFees);
			_mint(treasury, feeShares);
		}

		emit Harvest(treasury, profit, _performanceFee, _managementFee, feeShares, tvl);

		vaultTvl = tvl;

		// TODO computing lockedProfit for all profits is a bit heavy-handed
		// in reality it should only apply to the immediate profits from startegy's harvest
		// we can do this if we issue the strategy harvest call from inside this method

		// keep previous locked profits + add current profits
		uint256 newLockedProfit = totalFees > profit
			? 0
			: (profit - totalFees).mulDivDown(totalSupply(), tvl);
		maxLockedProfit = lockedProfit() + newLockedProfit;

		// we use 3/4 of the interval for locked profits
		lastHarvestInterval = ((timestamp - lastHarvestTimestamp) * 3) / 4;
		lastHarvestTimestamp = timestamp;
	}

	/// @notice Calculates the current amount of locked profit.
	/// @return The current amount of locked profit.
	function lockedProfit() public view returns (uint256) {
		// Get the last harvest and harvest delay.
		uint256 previousHarvest = lastHarvestTimestamp;
		uint256 harvestInterval = lastHarvestInterval;

		unchecked {
			// If the harvest delay has passed, there is no locked profit.
			// Cannot overflow on human timescales since harvestInterval is capped.
			if (block.timestamp >= previousHarvest + harvestInterval) return 0;

			// Get the maximum amount we could return.
			uint256 maximumLockedProfit = maxLockedProfit;

			// Compute how much profit remains locked based on the last harvest and harvest delay.
			// It's impossible for the previous harvest to be in the future, so this will never underflow.
			return
				maximumLockedProfit -
				(maximumLockedProfit * (block.timestamp - previousHarvest)) /
				harvestInterval;
		}
	}

	function _checkSlippage(
		uint256 expectedValue,
		uint256 actualValue,
		uint256 maxDelta
	) internal pure {
		uint256 delta = expectedValue > actualValue
			? expectedValue - actualValue
			: actualValue - expectedValue;
		if (delta > maxDelta) revert SlippageExceeded();
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
		emit DepositIntoStrategy(msg.sender, underlyingAmount);
	}

	/// @notice slippage is computed in underlying
	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) public onlyRole(GUARDIAN) {
		uint256 yieldTokenAmnt = convertToAssets(shares);
		(uint256 underlyingWithdrawn, ) = _stratRedeem(address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
		emit WithdrawFromStrategy(msg.sender, underlyingWithdrawn);
	}

	function closePosition(uint256 minAmountOut, uint256 slippageParam) public onlyRole(GUARDIAN) {
		uint256 underlyingWithdrawn = _stratClosePosition(slippageParam);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
		emit ClosePosition(msg.sender, underlyingWithdrawn);
	}

	/// @notice this method allows an arbitrary method to be called by the owner in case of emergency
	/// owner must be a timelock contract in order to allow users to redeem funds in case they suspect
	/// this action to be malicious
	function emergencyAction(address target, bytes calldata callData) public onlyOwner {
		Address.functionCall(target, callData);
		emit EmergencyAction(target, callData);
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

	function totalAssets() public view override returns (uint256) {
		return _selfBalance(yieldToken);
	}

	function isPaused() public view returns (bool) {
		return uBalance > 0;
	}

	// used for estimates only
	function exchangeRateUnderlying() public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return _stratCollateralToUnderlying();
		uint256 tvl = underlying.balanceOf(address(this)) + _strategyTvl();
		return tvl.mulDivUp(ONE, _totalSupply);
	}

	function getUpdatedUnderlyingBalance(address user) external returns (uint256) {
		uint256 userBalance = balanceOf(user);
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0 || userBalance == 0) return 0;
		uint256 tvl = underlying.balanceOf(address(this)) + _stratGetAndUpdateTvl();
		return (tvl * userBalance) / _totalSupply;
	}

	function underlyingBalance(address user) external view returns (uint256) {
		uint256 userBalance = balanceOf(user);
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0 || userBalance == 0) return 0;
		uint256 tvl = underlying.balanceOf(address(this)) + _strategyTvl();
		uint256 adjustedShares = (userBalance * (_totalSupply - lockedProfit())) / _totalSupply;
		return (tvl * adjustedShares) / _totalSupply;
	}

	function underlyingToShares(uint256 uAmnt) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return uAmnt.mulDivDown(ONE, _stratCollateralToUnderlying());
		return uAmnt.mulDivDown(_totalSupply, getTvl());
	}

	function sharesToUnderlying(uint256 shares) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return (shares * _stratCollateralToUnderlying()) / ONE;
		uint256 adjustedShares = (shares * (_totalSupply - lockedProfit())) / _totalSupply;
		return adjustedShares.mulDivDown(getTvl(), _totalSupply);
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

	/// make sure to override this - actual logic should use floating strategy balances
	function _getFloatingAmount(address token)
		internal
		view
		virtual
		override
		returns (uint256 fltAmnt)
	{
		if (token == address(underlying)) return underlying.balanceOf(strategy);
		if (token == NATIVE) return address(this).balance;
	}

	function decimals() public pure override returns (uint8) {
		return 18;
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

	function getBaseTokens() external view virtual override returns (address[] memory res) {
		res[0] = address(underlying);
	}

	function isValidBaseToken(address token) public view virtual override returns (bool) {
		return token == address(underlying);
	}

	// send funds to strategy
	function _transferIn(
		address token,
		address from,
		uint256 amount
	) internal virtual override {
		address to = sendERC20ToStrategy ? strategy : address(this);
		IERC20(token).safeTransferFrom(from, to, amount);
		// if (token == NATIVE) {
		// 	// if strategy logic lives in this contract, don't do anything
		// 	if (strategy != address(this)) return SafeETH.safeTransferETH(to, amount);
		// } else IERC20(token).safeTransferFrom(from, to, amount);
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
			IERC20(token).safeTransfer(to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(address token) internal view virtual override returns (uint256) {
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}

	event WithdrawFromStrategy(address indexed caller, uint256 amount);
	event DepositIntoStrategy(address indexed caller, uint256 amount);
	event ClosePosition(address indexed caller, uint256 amount);
	event EmergencyAction(address target, bytes callData);

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
