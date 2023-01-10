// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, IERC20, ERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { Auth } from "../../common/Auth.sol";
import { Fees } from "../../common/Fees.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { SCYStrategy, Strategy } from "./SCYStrategy.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { EAction, HarvestSwapParams } from "../../interfaces/Structs.sol";
import { VaultType, EpochType } from "../../interfaces/Structs.sol";
import { BatchedWithdrawEpoch } from "../../common/BatchedWithdrawEpoch.sol";
import { SectorErrors } from "../../interfaces/SectorErrors.sol";

// import "hardhat/console.sol";

abstract contract SCYWEpochVault is SCYStrategy, SCYBase, Fees, BatchedWithdrawEpoch {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	VaultType public constant vaultType = VaultType.Strategy;
	// inherits epochType from BatchedWithdrawEpoch
	// EpochType public constant epochType = EpochType.Withdraw;

	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 performanceFee,
		uint256 managementFee,
		uint256 sharesFees,
		uint256 tvl
	);

	uint256 public lastHarvestTimestamp;

	address payable public strategy;

	// immutables
	address public immutable override yieldToken;
	uint16 public immutable strategyId; // strategy-specific id ex: for MasterChef or 1155
	bool public acceptsNativeToken;
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
		acceptsNativeToken = _strategy.acceptsNativeToken;
		maxTvl = _strategy.maxTvl;

		lastHarvestTimestamp = block.timestamp;
		if (sendERC20ToStrategy() == true) revert DontSendERCToStrat();
	}

	// we should never send tokens directly to strategy for Epoch-based vaults
	function sendERC20ToStrategy() public pure override returns (bool) {
		return false;
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
		IWETH(address(underlying)).deposit{ value: msg.value }();
	}

	function _deposit(
		address,
		address token,
		uint256 amount
	) internal override isInitialized returns (uint256 sharesOut) {
		if (vaultTvl + amount > getMaxTvl()) revert MaxTvlReached();

		// if we have any float in the contract we cannot do deposit accounting
		uint256 _totalAssets = totalAssets();
		if (uBalance > 0 && _totalAssets > 0) revert DepositsPaused();

		// TODO should we handle this logic inside _stratDeposit?
		// this may be useful when a given strategy only accepts NATIVE tokens
		if (token == NATIVE) _depositNative();

		// if the strategy is active, we can deposit dirictly into strategy
		// if not, we deposit into the vault for a future strategy deposit
		if (_totalAssets > 0) {
			uint256 yieldTokenAdded = _stratDeposit(amount);
			// don't include newly minted shares and pendingRedeem in the calculation
			sharesOut = toSharesAfterDeposit(yieldTokenAdded);
		} else {
			sharesOut = underlyingToShares(amount);
			uBalance += amount;
		}

		vaultTvl += amount;
	}

	function _redeem(
		address,
		address token,
		uint256
	) internal override returns (uint256 amountTokenOut, uint256 amountToTransfer) {
		uint256 sharesToRedeem;
		(amountTokenOut, sharesToRedeem) = _redeem(msg.sender);
		_burn(address(this), sharesToRedeem);

		if (token == NATIVE) IWETH(address(underlying)).withdraw(amountTokenOut);
		return (amountTokenOut, amountTokenOut);
	}

	/// @notice harvest strategy
	function harvest(
		uint256 expectedTvl,
		uint256 maxDelta,
		HarvestSwapParams[] calldata swap1,
		HarvestSwapParams[] calldata swap2
	) external onlyRole(MANAGER) returns (uint256[] memory harvest1, uint256[] memory harvest2) {
		/// TODO refactor this
		uint256 _uBalance = underlying.balanceOf(address(this));
		uint256 startTvl = _stratGetAndUpdateTvl() + _uBalance;

		_checkSlippage(expectedTvl, startTvl, maxDelta);

		if (swap1.length > 0 || swap2.length > 0)
			(harvest1, harvest2) = _stratHarvest(swap1, swap2);

		uint256 tvl = _strategyTvl() + _uBalance;

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

		lastHarvestTimestamp = timestamp;
	}

	// minAmountOut is a slippage parameter for withdrawing requestedRedeem shares
	function processRedeem(uint256 minAmountOut) public override onlyRole(MANAGER) {
		uint256 _totalSupply = totalSupply();

		uint256 yeildTokenRedeem = convertToAssets(requestedRedeem);

		// account for any extra underlying balance to avoide DOS attacks
		uint256 balance = underlying.balanceOf(address(this));
		if (balance > (pendingWithdrawU + uBalance)) {
			uint256 extraFloat = balance - (pendingWithdrawU + uBalance);
			uBalance += extraFloat;
		}

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		// TODO why not use underlying.balanceOf?
		uint256 reserves = uBalance;
		uint256 shareOfReserves = (reserves * requestedRedeem) / _totalSupply;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) uBalance -= shareOfReserves;

		uint256 stratTvl = _stratGetAndUpdateTvl();
		(uint256 amountTokenOut, ) = stratTvl == 0
			? (0, 0)
			: _stratRedeem(address(this), yeildTokenRedeem);
		emit WithdrawFromStrategy(msg.sender, amountTokenOut);

		amountTokenOut += shareOfReserves;

		// its possible that cached vault tvl is lower than actual tvl
		uint256 _vaultTvl = vaultTvl;
		vaultTvl = _vaultTvl > amountTokenOut ? _vaultTvl - amountTokenOut : 0;

		if (amountTokenOut < minAmountOut) revert InsufficientOut(amountTokenOut, minAmountOut);

		// manually compute redeem shares here
		_processRedeem((1e18 * amountTokenOut) / requestedRedeem);
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
		onlyRole(MANAGER)
	{
		if (underlyingAmount > uBalance) revert NotEnoughUnderlying();
		uBalance -= underlyingAmount;
		uint256 yAdded = _stratDeposit(underlyingAmount);
		uint256 virtualSharesOut = toSharesAfterDeposit(yAdded);
		if (virtualSharesOut < minAmountOut) revert SlippageExceeded();
		emit DepositIntoStrategy(msg.sender, underlyingAmount);
	}

	/// @notice slippage is computed in underlying
	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) public onlyRole(MANAGER) {
		uint256 yieldTokenAmnt = convertToAssets(shares);
		(uint256 underlyingWithdrawn, ) = _stratRedeem(address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
		emit WithdrawFromStrategy(msg.sender, underlyingWithdrawn);
	}

	function closePosition(uint256 minAmountOut, uint256 slippageParam) public onlyRole(MANAGER) {
		uint256 underlyingWithdrawn = _stratClosePosition(slippageParam);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn;
		emit ClosePosition(msg.sender, underlyingWithdrawn);
	}

	/// @notice this method allows an arbitrary method to be called by the owner in case of emergency
	/// owner must be a timelock contract in order to allow users to redeem funds in case they suspect
	/// this action to be malicious
	function emergencyAction(EAction[] calldata actions) public onlyOwner {
		uint256 l = actions.length;
		for (uint256 i = 0; i < l; i++) {
			address target = actions[i].target;
			bytes memory data = actions[i].data;
			(bool success, ) = target.call{ value: actions[i].value }(data);
			require(success, "emergencyAction failed");
			emit EmergencyAction(target, data);
		}
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
		return (tvl * userBalance) / _totalSupply;
	}

	function underlyingToShares(uint256 uAmnt) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return uAmnt.mulDivDown(ONE, _stratCollateralToUnderlying());
		return uAmnt.mulDivDown(_totalSupply, getTvl());
	}

	function sharesToUnderlying(uint256 shares) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return (shares * _stratCollateralToUnderlying()) / ONE;
		return shares.mulDivDown(getTvl(), _totalSupply);
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
	function getFloatingAmount(address token)
		public
		view
		virtual
		override
		returns (uint256 fltAmnt)
	{
		if (token == address(underlying)) return underlying.balanceOf(address(this)) - uBalance;
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
		if (acceptsNativeToken) {
			res = new address[](2);
			res[1] = NATIVE;
		} else res = new address[](1);
		res[0] = address(underlying);
	}

	function isValidBaseToken(address token) public view virtual override returns (bool) {
		return token == address(underlying) || (acceptsNativeToken && token == NATIVE);
	}

	// send funds to strategy
	function _transferIn(
		address token,
		address from,
		uint256 amount
	) internal virtual override {
		address to = address(this);
		IERC20(token).safeTransferFrom(from, to, amount);
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

	function totalSupply() public view override(SCYBase, ERC20) returns (uint256) {
		return ERC20.totalSupply();
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
	error DontSendERCToStrat();
}
