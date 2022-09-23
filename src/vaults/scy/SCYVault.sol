// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { Auth } from "../../common/Auth.sol";
import { Fees } from "../../common/Fees.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { Treasury } from "../../common/Treasury.sol";
import { Bank } from "../../bank/Bank.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SCYStrategy, Strategy } from "./SCYStrategy.sol";

// import "hardhat/console.sol";

abstract contract SCYVault is SCYStrategy, SCYBase, Fees, Treasury {
	using SafeERC20 for IERC20;
	using SafeCast for uint256;

	Bank public bank;
	address public strategy;

	// immutables
	bytes32 private immutable _symbol;
	uint256 public immutable strategyId; // strategy-specific id ex: for MasterChef or 1155
	address public immutable yieldToken;
	IERC20 public immutable underlying;

	uint96 public maxDust; // minimal amount of underlying token allowed before deposits are paused
	uint256 public maxTvl; // pack all params and balances
	uint256 public strategyTvl; // strategy balance in underlying
	uint256 public uBalance; // underlying balance held by vault
	uint256 public yBalance; // yield token balance held by vault

	event MaxDustUpdated(uint256 maxDust);
	event MaxTvlUpdated(uint256 maxTvl);
	event StrategyUpdated(address strategy);

	modifier isInitialized() {
		if (strategy == address(0)) revert NotInitialized();
		_;
	}

	constructor(
		address _bank,
		address _owner,
		address guardian,
		address manager,
		address _treasury,
		Strategy memory _strategy
	) Auth(_owner, guardian, manager) {
		treasury = _treasury;
		bank = Bank(_bank);

		// strategy init
		_symbol = _strategy.symbol;
		strategy = _strategy.addr;
		maxDust = _strategy.maxDust;
		strategyId = _strategy.strategyId;
		yieldToken = _strategy.yieldToken;
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
		maxTvl = _maxTvl.toUint128();
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
		address receiver,
		address,
		uint256 amount
	) internal override isInitialized returns (uint256 amountSharesOut) {
		// if we have any float in the contract we cannot do deposit accounting
		if (isPaused()) revert DepositsPaused();

		uint256 yAdded = _stratDeposit(amount);
		uint256 endYieldToken = yAdded + yBalance;

		amountSharesOut = bank.deposit(0, receiver, yAdded, endYieldToken);
		yBalance += yAdded.toUint128();
	}

	function _redeem(
		address receiver,
		address,
		uint256 sharesToRedeem
	) internal override returns (uint256 amountTokenOut, uint256 amountToTransfer) {
		uint256 _totalSupply = _selfBalance(yieldToken);
		uint256 yeildTokenAmnt = bank.withdraw(0, receiver, sharesToRedeem, _totalSupply);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		uint256 reserves = uBalance;
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalSupply;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) uBalance -= shareOfReserves.toUint128();

		// decrease yeild token amnt
		yBalance -= yeildTokenAmnt.toUint128();

		// if we also need to send the user share of reserves, we allways withdraw to vault first
		// if we don't we can have strategy withdraw directly to user if possible
		if (shareOfReserves > 0) {
			(amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenAmnt);
			amountTokenOut += shareOfReserves;
			amountToTransfer += amountToTransfer;
		} else (amountTokenOut, amountToTransfer) = _stratRedeem(receiver, yeildTokenAmnt);
	}

	// DoS attack is possible by depositing small amounts of underlying
	// can make it costly by using a maxDust amnt, ex: $100
	// TODO: make sure we don't need check
	function isPaused() public view returns (bool) {
		return uBalance > maxDust;
	}

	/// @notice Harvest a set of trusted strategies.
	/// strategiesparam is for backwards compatibility.
	/// @dev Will always revert if called outside of an active
	/// harvest window or before the harvest delay has passed.
	function harvest(address[] calldata) external onlyRole(MANAGER) {
		uint256 tvl = _stratGetAndUpdateTvl();
		uint256 strategyBalance = strategyTvl;
		if (tvl <= strategyBalance) return;

		bank.takeFees(0, address(this), tvl - strategyBalance, _selfBalance(yieldToken));
		yBalance -= _selfBalance(yieldToken).toUint128();
		strategyTvl = tvl.toUint128();
	}

	/// ***Note: slippage is computed in yield token amnt, not shares
	function depositIntoStrategy(uint256 underlyingAmount, uint256 minAmountOut)
		public
		onlyRole(GUARDIAN)
	{
		if (underlyingAmount > uBalance) revert NotEnoughUnderlying();
		uBalance -= underlyingAmount.toUint128();
		underlying.safeTransfer(strategy, underlyingAmount);
		uint256 yAdded = _stratDeposit(underlyingAmount);
		if (yAdded < minAmountOut) revert SlippageExceeded();
		yBalance += yAdded.toUint128();
	}

	// note: slippage is computed in underlying
	function withdrawFromStrategy(uint256 shares, uint256 minAmountOut) public onlyRole(GUARDIAN) {
		uint256 totalShares = bank.totalShares(address(this), 0);
		uint256 yieldTokenAmnt = (shares * _selfBalance(yieldToken)) / totalShares;
		yBalance -= yieldTokenAmnt.toUint128();
		(uint256 underlyingWithdrawn, ) = _stratRedeem(address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn.toUint128();
	}

	function closePosition(uint256 minAmountOut) public onlyRole(GUARDIAN) {
		yBalance = 0;
		uint256 underlyingWithdrawn = _stratClosePosition();
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		uBalance += underlyingWithdrawn.toUint128();
	}

	function getStrategyTvl() public view returns (uint256) {
		return _strategyTvl();
	}

	// used for estimates only
	function exchangeRateUnderlying() public view returns (uint256) {
		uint256 totalShares = bank.totalShares(address(this), 0);
		if (totalShares == 0) return _stratCollateralToUnderlying();
		return ((underlying.balanceOf(address(this)) + _strategyTvl() + 1) * ONE) / totalShares;
	}

	function underlyingBalance(address user) external view returns (uint256) {
		uint256 token = bank.getTokenId(address(this), 0);
		uint256 userBalance = bank.balanceOf(user, token);
		uint256 totalShares = bank.totalShares(address(this), 0);
		if (totalShares == 0 || userBalance == 0) return 0;
		return
			(((underlying.balanceOf(address(this)) * userBalance) / totalShares + _strategyTvl()) *
				userBalance) / totalShares;
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

	function underlyingDecimals(uint96) public view returns (uint8) {
		return IERC20Metadata(address(underlying)).decimals();
	}

	function symbol() public view returns (string memory) {
		return string(abi.encodePacked(_symbol));
	}

	function decimals(uint96) public view returns (uint8) {
		return IERC20Metadata(yieldToken).decimals();
	}

	/**
	 * @dev See {ISuperComposableYield-exchangeRateCurrent}
	 */
	function exchangeRateCurrent() public view virtual override returns (uint256) {
		uint256 totalShares = bank.totalShares(address(this), 0);
		if (totalShares == 0) return ONE;
		return (_selfBalance(yieldToken) * ONE) / totalShares;
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
		if (token == strategy) return IERC20(token).balanceOf(address(this));
		return (token == NATIVE) ? strategyTvl : IERC20(token).balanceOf(strategy);
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
