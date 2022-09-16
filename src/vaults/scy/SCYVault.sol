// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase, Initializable, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { AuthU } from "../../common/AuthU.sol";
import { FeesU } from "../../common/FeesU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { TreasuryU } from "../../common/TreasuryU.sol";
import { Bank } from "../../bank/Bank.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { SCYStrategy, Strategy } from "./SCYStrategy.sol";
import { IMX } from "../../strategies/imx/IMX.sol";

// import "hardhat/console.sol";

abstract contract SCYVault is Initializable, SCYStrategy, SCYBase, FeesU, TreasuryU {
	using SafeERC20 for IERC20;
	using SafeCast for uint256;

	Bank public bank;

	Strategy[] public strategies;
	// mapping should account for masterChef and other 1155 contracts
	mapping(address => mapping(uint256 => uint96)) public strategyIndexes;

	// TOOD: strategy-specific?
	uint256 public maxDust; // minimal amount of underlying token allowed before deposits are paused

	event MaxDustUpdated(uint256 maxDust);
	event MaxTvlUpdated(uint96 id, uint256 maxTvl);
	event StrategyUpdated(uint96 id, address strategy);

	modifier strategyExists(uint96 id) {
		if (!strategies[id].exists) revert StrategyDoesntExist();
		_;
	}

	function initialize(
		address _bank,
		address _owner,
		address guardian,
		address manager,
		address _treasury
	) public initializer {
		__Auth_init_(_owner, guardian, manager);
		treasury = _treasury;
		bank = Bank(_bank);
	}

	function addStrategy(Strategy calldata strategy) public onlyOwner returns (uint96 id) {
		address addr = strategy.addr;
		uint256 index = strategyIndexes[addr][strategy.strategyId];
		id = (strategies.length).toUint96();
		if (index < id && strategies[index].exists) revert StrategyExists();
		strategies.push(
			Strategy({
				addr: strategy.addr,
				exists: true,
				strategyId: strategy.strategyId,
				yieldToken: strategy.yieldToken,
				underlying: strategy.underlying,
				maxTvl: strategy.maxTvl,
				balance: 0,
				uBalance: 0,
				yBalance: 0
			})
		);
		strategyIndexes[addr][strategy.strategyId] = id;
		emit StrategyUpdated(id, addr);
	}

	/*///////////////////////////////////////////////////////////////
                    CONFIG
    //////////////////////////////////////////////////////////////*/

	function getMaxTvl(uint96 id) public view returns (uint256 maxTvl) {
		Strategy storage strategy = strategies[id];
		return min(strategy.maxTvl, _stratMaxTvl(strategy));
	}

	function setMaxTvl(uint96 id, uint256 maxTvl) public strategyExists(id) onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		strategy.maxTvl = maxTvl.toUint128();
		emit MaxTvlUpdated(id, min(maxTvl, _stratMaxTvl(strategy)));
	}

	function setMaxDust(uint256 maxDust_) public onlyRole(GUARDIAN) {
		maxDust = maxDust_;
		emit MaxDustUpdated(maxDust_);
	}

	function _deposit(
		uint96 id,
		address receiver,
		address,
		uint256 amount
	) internal override strategyExists(id) returns (uint256 amountSharesOut) {
		// if we have any float in the contract we cannot do deposit accounting
		require(!isPaused(id), "Vault: DEPOSITS_PAUSED");

		Strategy storage strategy = strategies[id];
		uint256 yAdded = _stratDeposit(strategy, amount);
		uint256 endYieldToken = yAdded + strategy.yBalance;

		amountSharesOut = bank.deposit(id, receiver, yAdded, endYieldToken);
		strategy.yBalance += yAdded.toUint128();
	}

	function _redeem(
		uint96 id,
		address receiver,
		address,
		uint256 sharesToRedeem
	)
		internal
		override
		strategyExists(id)
		returns (uint256 amountTokenOut, uint256 amountToTransfer)
	{
		Strategy storage strategy = strategies[id];
		address yToken = strategy.yieldToken;

		uint256 _totalSupply = _selfBalance(id, yToken);
		uint256 yeildTokenAmnt = bank.withdraw(id, receiver, sharesToRedeem, _totalSupply);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		uint256 reserves = strategy.uBalance;
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalSupply;

		// Update strategy underlying reserves balance
		if (shareOfReserves > 0) strategy.uBalance -= shareOfReserves.toUint128();

		// decrease yeild token amnt
		strategy.yBalance -= yeildTokenAmnt.toUint128();

		// if we also need to send the user share of reserves, we allways withdraw to vault first
		// if we don't we can have strategy withdraw directly to user if possible
		if (shareOfReserves > 0) {
			(amountTokenOut, amountToTransfer) = _stratRedeem(strategy, receiver, yeildTokenAmnt);
			amountTokenOut += shareOfReserves;
			amountToTransfer += amountToTransfer;
		} else
			(amountTokenOut, amountToTransfer) = _stratRedeem(strategy, receiver, yeildTokenAmnt);
	}

	// DoS attack is possible by depositing small amounts of underlying
	// can make it costly by using a maxDust amnt, ex: $100
	// TODO: make sure we don't need check
	function isPaused(uint96 id) public view returns (bool) {
		return strategies[id].uBalance > maxDust;
	}

	/// @notice Harvest a set of trusted strategies.
	/// strategiesparam is for backwards compatibility.
	/// @dev Will always revert if called outside of an active
	/// harvest window or before the harvest delay has passed.
	function harvest(uint96 id, address[] calldata) external onlyRole(MANAGER) {
		Strategy storage strategy = strategies[id];
		uint256 tvl = _stratGetAndUpdateTvl(strategy);
		uint256 strategyBalance = strategy.balance;
		if (tvl <= strategyBalance) return;

		address yToken = strategy.yieldToken;
		bank.takeFees(id, address(this), tvl - strategyBalance, _selfBalance(id, yToken));
		strategy.yBalance -= _selfBalance(id, yToken).toUint128();
		strategy.balance = tvl.toUint128();
	}

	/// ***Note: slippage is computed in yield token amnt, not shares
	function depositIntoStrategy(
		uint96 id,
		uint256 underlyingAmount,
		uint256 minAmountOut
	) public onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		if (underlyingAmount > strategy.uBalance) revert NotEnoughUnderlying();
		strategy.uBalance -= underlyingAmount.toUint128();
		strategy.underlying.safeTransfer(strategy.addr, underlyingAmount);
		uint256 yAdded = _stratDeposit(strategy, underlyingAmount);
		if (yAdded < minAmountOut) revert SlippageExceeded();
		strategy.yBalance += yAdded.toUint128();
	}

	// note: slippage is computed in underlying
	function withdrawFromStrategy(
		uint96 id,
		uint256 shares,
		uint256 minAmountOut
	) public onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		uint256 totalShares = bank.totalShares(address(this), id);
		uint256 yieldTokenAmnt = (shares * _selfBalance(id, strategy.yieldToken)) / totalShares;
		strategy.yBalance -= yieldTokenAmnt.toUint128();
		(uint256 underlyingWithdrawn, ) = _stratRedeem(strategy, address(this), yieldTokenAmnt);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		strategy.uBalance += underlyingWithdrawn.toUint128();
	}

	function closePosition(uint96 id, uint256 minAmountOut) public onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		strategy.yBalance = 0;
		uint256 underlyingWithdrawn = _stratClosePosition(strategy);
		if (underlyingWithdrawn < minAmountOut) revert SlippageExceeded();
		strategy.uBalance += underlyingWithdrawn.toUint128();
	}

	function underlying(uint96 id) public view returns (IERC20) {
		return strategies[id].underlying;
	}

	function getStrategyId(address strategy, uint256 strategyId) public view returns (uint96) {
		return strategyIndexes[strategy][strategyId];
	}

	function getStrategy(uint96 id) public view returns (Strategy memory) {
		return strategies[id];
	}

	function getStrategyTvl(uint96 id) public view returns (uint256) {
		return _strategyTvl(strategies[id]);
	}

	// used for estimates only
	function exchangeRateUnderlying(uint96 id) public view returns (uint256) {
		Strategy storage strategy = strategies[id];
		uint256 totalShares = bank.totalShares(address(this), id);
		if (totalShares == 0) return _stratCollateralToUnderlying(strategy);
		return
			((strategy.underlying.balanceOf(address(this)) + _strategyTvl(strategy) + 1) * ONE) /
			totalShares;
	}

	function underlyingBalance(uint96 id, address user) external view returns (uint256) {
		Strategy storage strategy = strategies[id];
		uint256 token = bank.getTokenId(address(this), id);
		uint256 balance = bank.balanceOf(user, token);
		uint256 totalShares = bank.totalShares(address(this), id);
		if (totalShares == 0 || balance == 0) return 0;
		return
			(((strategy.underlying.balanceOf(address(this)) * balance) /
				totalShares +
				_strategyTvl(strategy)) * balance) / totalShares;
	}

	function underlyingToShares(uint96 id, uint256 uAmnt) public view returns (uint256) {
		return ((ONE * uAmnt) / exchangeRateUnderlying(id));
	}

	function sharesToUnderlying(uint96 id, uint256 shares) public view returns (uint256) {
		return (shares * exchangeRateUnderlying(id)) / ONE;
	}

	///
	///  Yield Token Overrides
	///

	function assetInfo(uint96 id)
		public
		view
		returns (
			AssetType assetType,
			address assetAddress,
			uint8 assetDecimals
		)
	{
		address yToken = strategies[id].yieldToken;
		return (AssetType.LIQUIDITY, yToken, IERC20Metadata(yToken).decimals());
	}

	function underlyingDecimals(uint96 id) public view returns (uint8) {
		return IERC20Metadata(address(strategies[id].underlying)).decimals();
	}

	function decimals(uint96 id) public view returns (uint8) {
		return IERC20Metadata(strategies[id].yieldToken).decimals();
	}

	/**
	 * @dev See {ISuperComposableYield-exchangeRateCurrent}
	 */
	function exchangeRateCurrent(uint96 id) public view virtual override returns (uint256) {
		uint256 totalShares = bank.totalShares(address(this), id);
		if (totalShares == 0) return ONE;
		return (_selfBalance(id, strategies[id].yieldToken) * ONE) / totalShares;
	}

	/**
	 * @dev See {ISuperComposableYield-exchangeRateStored}
	 */
	function yieldToken(uint96 id) external view returns (address) {
		return strategies[id].yieldToken;
	}

	function exchangeRateStored(uint96 id) external view virtual override returns (uint256) {
		return exchangeRateCurrent(id);
	}

	function getBaseTokens(uint96 id) external view override returns (address[] memory res) {
		res[0] = address(strategies[id].underlying);
	}

	function isValidBaseToken(uint96 id, address token) public view override returns (bool) {
		return token == address(strategies[id].underlying);
	}

	// send funds to strategy
	function _transferIn(
		uint96 id,
		address token,
		address from,
		uint256 amount
	) internal virtual override {
		if (token == NATIVE) {
			// if strategy logic lives in this contract, don't do anything
			address stratAddr = strategies[id].addr;
			if (stratAddr == address(this))
				return SafeETH.safeTransferETH(strategies[id].addr, amount);
		} else IERC20(token).safeTransferFrom(from, strategies[id].addr, amount);
	}

	// send funds to user
	function _transferOut(
		uint96 id,
		address token,
		address to,
		uint256 amount
	) internal virtual override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransferFrom(strategies[id].addr, to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(uint96 id, address token)
		internal
		view
		virtual
		override
		returns (uint256)
	{
		return
			(token == NATIVE)
				? strategies[id].addr.balance
				: IERC20(token).balanceOf(strategies[id].addr);
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}

	error StrategyExists();
	error StrategyDoesntExist();
	error NotEnoughUnderlying();
	error SlippageExceeded();
	error BadStaticCall();
}
