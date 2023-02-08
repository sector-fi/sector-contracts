// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import { SCYBaseU, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBaseU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { EAction, HarvestSwapParams } from "../../interfaces/Structs.sol";
import { VaultType, EpochType } from "../../interfaces/Structs.sol";
import { SectorErrors } from "../../interfaces/SectorErrors.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { SCYVaultConfig } from "../../interfaces/ERC5115/ISCYVault.sol";
import { AuthConfig } from "../../common/Auth.sol";
import { FeeConfig } from "../../common/Fees.sol";

// import "hardhat/console.sol";

contract SCYVaultU is SCYBaseU {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	VaultType public constant vaultType = VaultType.Strategy;
	EpochType public constant epochType = EpochType.None;

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

	ISCYStrategy public strategy;

	// immutables
	address public override yieldToken;
	uint16 public strategyId; // strategy-specific id ex: for MasterChef or 1155
	bool public acceptsNativeToken;
	IERC20 public underlying;

	uint256 public maxTvl; // pack all params and balances
	uint256 public vaultTvl; // strategy balance in underlying
	uint256 public uBalance; // underlying balance held by vault

	event MaxTvlUpdated(uint256 maxTvl);
	event StrategyUpdated(address strategy);

	modifier isInitialized() {
		if (address(strategy) == address(0)) revert NotInitialized();
		_;
	}

	function initialize(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		SCYVaultConfig memory vaultConfig
	) external initializer {
		__Auth_init(authConfig);
		__Fees_init(feeConfig);
		__SCYBase_init(vaultConfig.name, vaultConfig.symbol);

		// vault init
		yieldToken = vaultConfig.yieldToken;
		strategy = ISCYStrategy(vaultConfig.addr);
		strategyId = vaultConfig.strategyId;
		underlying = vaultConfig.underlying;
		acceptsNativeToken = vaultConfig.acceptsNativeToken;
		maxTvl = vaultConfig.maxTvl;

		lastHarvestTimestamp = block.timestamp;
	}

	/*///////////////////////////////////////////////////////////////
                    CONFIG
    //////////////////////////////////////////////////////////////*/

	function getMaxTvl() public view returns (uint256) {
		return min(maxTvl, strategy.getMaxTvl());
	}

	function setMaxTvl(uint256 _maxTvl) public onlyRole(GUARDIAN) {
		maxTvl = _maxTvl;
		emit MaxTvlUpdated(min(maxTvl, strategy.getMaxTvl()));
	}

	function initStrategy(address _strategy) public onlyRole(GUARDIAN) {
		if (address(strategy) != address(0)) revert NoReInit();
		strategy = ISCYStrategy(_strategy);
		_validateStrategy();
		emit StrategyUpdated(_strategy);
	}

	function updateStrategy(address _strategy) public onlyOwner {
		uint256 tvl = strategy.getAndUpdateTvl();
		if (tvl > 0) revert InvalidStrategyUpdate();
		strategy = ISCYStrategy(_strategy);
		_validateStrategy();
		emit StrategyUpdated(_strategy);
	}

	function _validateStrategy() internal view {
		if (strategy.underlying() != underlying) revert InvalidStrategy();
	}

	function _depositNative() internal override {
		IWETH(address(underlying)).deposit{ value: msg.value }();
		if (sendERC20ToStrategy()) underlying.safeTransfer(address(strategy), msg.value);
	}

	function _deposit(
		address,
		address token,
		uint256 amount
	) internal override isInitialized returns (uint256 sharesOut) {
		if (vaultTvl + amount > getMaxTvl()) revert MaxTvlReached();
		// if we have any float in the contract we cannot do deposit accounting
		if (uBalance > 0) revert DepositsPaused();
		// TODO should we handle this logic inside _stratDeposit?
		// this may be useful when a given strategy only accepts NATIVE tokens
		if (token == NATIVE) _depositNative();
		uint256 yieldTokenAdded = strategy.deposit(amount);
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
		uint256 adjustedShares = (sharesToRedeem * _totalSupply) / (_totalSupply + lockedProfit());
		uint256 yeildTokenRedeem = convertToAssets(adjustedShares);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		// TODO why not use underlying.balanceOf?
		uint256 reserves = uBalance;
		uint256 shareOfReserves = (reserves * adjustedShares) / _totalSupply;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) uBalance -= shareOfReserves;

		receiver = token == NATIVE ? address(this) : receiver;

		// if we also need to send the user share of reserves, we allways withdraw to vault first
		// if we don't we can have strategy withdraw directly to user if possible
		if (shareOfReserves > 0) {
			amountTokenOut = strategy.redeem(receiver, yeildTokenRedeem);
			amountTokenOut += shareOfReserves;
			amountToTransfer += shareOfReserves;
		} else amountTokenOut = strategy.redeem(receiver, yeildTokenRedeem);

		// its possible that cached vault tvl is lower than actual tvl
		uint256 _vaultTvl = vaultTvl;
		vaultTvl = _vaultTvl > amountTokenOut ? _vaultTvl - amountTokenOut : 0;

		// it requested token is native, convert to native
		if (token == NATIVE) {
			IWETH(address(underlying)).withdraw(amountTokenOut);
			// ensure that we are tranferring these tokens to the user
			amountToTransfer = amountTokenOut;
		}

		_burn(msg.sender, sharesToRedeem);
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
		uint256 startTvl = strategy.getAndUpdateTvl() + _uBalance;

		_checkSlippage(expectedTvl, startTvl, maxDelta);

		// this allows us to skip strategy harvest if needeed
		if (swap1.length > 0 || swap2.length > 0)
			(harvest1, harvest2) = strategy.harvest(swap1, swap2);

		uint256 tvl = strategy.getTvl() + _uBalance;

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

		// only use harvest profits in lockedProfit?
		uint256 lProfit = tvl > startTvl ? tvl - startTvl : 0;

		// keep previous locked profits + add current profits
		// locked profit is denominated in shares
		uint256 newLockedProfit;
		if (lProfit > totalFees) {
			uint256 lockedValue = lProfit - totalFees;
			newLockedProfit = (lockedValue).mulDivDown(totalSupply(), tvl - lockedValue);
		}
		maxLockedProfit = lockedProfit() + newLockedProfit;

		// we use 3/4 of the interval for locked profits
		lastHarvestInterval = ((timestamp - lastHarvestTimestamp) * 3) / 4;
		lastHarvestTimestamp = timestamp;
	}

	/// @notice Calculates the current amount of locked profit.
	/// lockedProfit is denominated in shares and is used to inflate total supplly	on withdrawal
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
		underlying.safeTransfer(address(strategy), underlyingAmount);
		uint256 yAdded = strategy.deposit(underlyingAmount);
		uint256 virtualSharesOut = convertToShares(yAdded);
		if (virtualSharesOut < minAmountOut) revert SlippageExceeded();
		emit DepositIntoStrategy(msg.sender, underlyingAmount);
	}

	/// @notice slippage is computed in underlying
	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) public onlyRole(GUARDIAN) {
		uint256 yieldTokenAmnt = convertToAssets(shares);
		uint256 underlyingWithdrawn = strategy.redeem(address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance = underlying.balanceOf(address(this));
		emit WithdrawFromStrategy(msg.sender, underlyingWithdrawn);
	}

	function closePosition(uint256 minAmountOut, uint256 slippageParam) public onlyRole(MANAGER) {
		uint256 underlyingWithdrawn = strategy.closePosition(slippageParam);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance = underlying.balanceOf(address(this));
		emit ClosePosition(msg.sender, underlyingWithdrawn);
	}

	/// @notice this method allows an arbitrary method to be called by the owner in case of emergency
	/// owner must be a timelock contract in order to allow users to redeem funds in case they suspect
	/// this action to be malicious
	function emergencyAction(EAction[] calldata actions) public payable onlyOwner {
		uint256 l = actions.length;
		for (uint256 i; i < l; ++i) {
			address target = actions[i].target;
			bytes memory data = actions[i].data;
			(bool success, ) = target.call{ value: actions[i].value }(data);
			require(success, "emergencyAction failed");
			emit EmergencyAction(target, data);
		}
	}

	function getStrategyTvl() public view returns (uint256) {
		return strategy.getTvl();
	}

	/// no slippage check - slippage can be done on vault level
	/// against total expected balance of all strategies
	function getAndUpdateTvl() public returns (uint256 tvl) {
		uint256 stratTvl = strategy.getAndUpdateTvl();
		uint256 balance = underlying.balanceOf(address(this));
		tvl = balance + stratTvl;
	}

	function getTvl() public view returns (uint256 tvl) {
		uint256 stratTvl = strategy.getTvl();
		uint256 balance = underlying.balanceOf(address(this));
		tvl = balance + stratTvl;
	}

	function totalAssets() public view override returns (uint256) {
		return strategy.getLpBalance();
	}

	function isPaused() public view returns (bool) {
		return uBalance > 0;
	}

	// used for estimates only
	function exchangeRateUnderlying() public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return strategy.collateralToUnderlying();
		uint256 tvl = underlying.balanceOf(address(this)) + strategy.getTvl();
		return tvl.mulDivUp(ONE, _totalSupply);
	}

	function getUpdatedUnderlyingBalance(address user) external returns (uint256) {
		uint256 userBalance = balanceOf(user);
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0 || userBalance == 0) return 0;
		uint256 tvl = underlying.balanceOf(address(this)) + strategy.getAndUpdateTvl();
		return (tvl * userBalance) / _totalSupply;
	}

	function underlyingBalance(address user) external view returns (uint256) {
		uint256 userBalance = balanceOf(user);
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0 || userBalance == 0) return 0;
		uint256 tvl = underlying.balanceOf(address(this)) + strategy.getTvl();
		uint256 adjustedShares = (userBalance * _totalSupply) / (_totalSupply + lockedProfit());
		return (tvl * adjustedShares) / _totalSupply;
	}

	function underlyingToShares(uint256 uAmnt) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		uint256 tvl = getTvl();
		if (_totalSupply == 0 || tvl == 0)
			return uAmnt.mulDivDown(ONE, strategy.collateralToUnderlying());
		return uAmnt.mulDivDown(_totalSupply, tvl);
	}

	function sharesToUnderlying(uint256 shares) public view returns (uint256) {
		uint256 _totalSupply = totalSupply();
		if (_totalSupply == 0) return (shares * strategy.collateralToUnderlying()) / ONE;
		uint256 adjustedShares = (shares * _totalSupply) / (_totalSupply + lockedProfit());
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
	function getFloatingAmount(address token)
		public
		view
		virtual
		override
		returns (uint256 fltAmnt)
	{
		if (token == address(underlying))
			return
				sendERC20ToStrategy()
					? underlying.balanceOf(address(strategy))
					: underlying.balanceOf(address(this)) - uBalance;
		if (token == NATIVE) return address(this).balance;
	}

	function decimals() public pure override returns (uint8) {
		return 18;
	}

	/// @dev used to compute slippage on withdraw
	function getWithdrawAmnt(uint256 shares) public view returns (uint256) {
		uint256 assets = convertToAssets(shares);
		return ISCYStrategy(strategy).getWithdrawAmnt(assets);
	}

	/// @dev used to compute slippage on deposit
	function getDepositAmnt(uint256 uAmnt) public view returns (uint256) {
		uint256 assets = ISCYStrategy(strategy).getDepositAmnt(uAmnt);
		return convertToShares(assets);
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
		address to = sendERC20ToStrategy() ? address(strategy) : address(this);
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
}
