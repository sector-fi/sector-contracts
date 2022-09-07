// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase1155, Initializable, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase1155.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { AuthU } from "../../common/AuthU.sol";
import { FeesU } from "../../common/FeesU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { TreasuryU } from "../../common/TreasuryU.sol";

// import "hardhat/console.sol";

contract SCYVault1155 is Initializable, SCYBase1155, FeesU, TreasuryU {
	using SafeERC20 for IERC20;

	IMX private _strategy;
	IERC20 private _underlying;
	uint256 public strategyBalance;
	uint256 private _maxTvl;
	uint256 public maxDust; // minimal amount of underlying token allowed before deposits are paused

	event MaxDustUpdated(uint256 maxDust);
	event MaxTvlUpdated(uint256 maxTvl);
	event StrategyUpdated(address strategy);

	modifier hasStrategy() {
		require(address(_strategy) != address(0), "SCYVault: NO STRAT");
		_;
	}

	function initialize(
		address _yieldToken,
		address _bank,
		address _treasury
	) public initializer {
		__SCYBase_init_(_yieldToken, _bank);
		treasury = _treasury;
	}

	function setStrategy(IMX strategy_) public onlyOwner {
		// TODO allow replacing strat
		require(address(_strategy) == address(0), "SCYVault: STRAT IS SET");
		_strategy = strategy_;
		_underlying = _strategy.underlying();
		emit StrategyUpdated(address(strategy_));
	}

	/*///////////////////////////////////////////////////////////////
                    CONFIG
    //////////////////////////////////////////////////////////////*/

	function getMaxTvl() public view returns (uint256 maxTvl) {
		return min(_maxTvl, _strategy.getMaxTvl());
	}

	function setMaxTvl(uint256 maxTvl_) public onlyRole(GUARDIAN) {
		_maxTvl = maxTvl_;
		emit MaxTvlUpdated(min(_maxTvl, _strategy.getMaxTvl()));
	}

	function setMaxDust(uint256 maxDust_) public onlyRole(GUARDIAN) {
		maxDust = maxDust_;
		emit MaxDustUpdated(maxDust_);
	}

	function _deposit(
		address receiver,
		address,
		uint256 amount
	) internal override hasStrategy returns (uint256 amountSharesOut) {
		// if we have any float in the contract we cannot do deposit accounting
		require(!isPaused(), "Vault: DEPOSITS_PAUSED");
		// uint256 exchangeRate = exchangeRateCurrent();
		uint256 startYieldToken = _selfBalance(yieldToken);
		_strategy.deposit(amount);
		uint256 endYieldToken = _selfBalance(yieldToken);

		amountSharesOut = bank.deposit(0, receiver, endYieldToken - startYieldToken, endYieldToken);
	}

	function _redeem(
		address receiver,
		address,
		uint256 sharesToRedeem
	) internal override hasStrategy returns (uint256 amountTokenOut) {
		uint256 _totalSupply = _selfBalance(yieldToken);
		uint256 yeildTokenAmnt = bank.withdraw(0, receiver, sharesToRedeem, _totalSupply);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		uint256 reserves = _underlying.balanceOf(address(this));
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalSupply;

		amountTokenOut = shareOfReserves + _strategy.redeem(yeildTokenAmnt);
	}

	// DoS attack is possible by depositing small amounts of underlying
	// can make it costly by using a maxDust amnt, ex: $100
	function isPaused() public view returns (bool) {
		return _underlying.balanceOf(address(this)) > maxDust;
	}

	/// @notice Harvest a set of trusted strategies.
	/// strategiesparam is for backwards compatibility.
	/// @dev Will always revert if called outside of an active
	/// harvest window or before the harvest delay has passed.
	function harvest(address[] calldata) external onlyRole(MANAGER) {
		uint256 tvl = _strategy.getAndUpdateTVL();
		if (tvl > strategyBalance)
			bank.takeFees(0, address(this), tvl - strategyBalance, _selfBalance(yieldToken));
		strategyBalance = tvl;
	}

	// TODO: add slippage
	function depositIntoStrategy(address, uint256 underlyingAmount) public onlyRole(GUARDIAN) {
		_underlying.safeTransfer(address(_strategy), underlyingAmount);
		_strategy.deposit(underlyingAmount);
	}

	// TODO: add slippage
	function withdrawFromStrategy(address, uint256 shares) public onlyRole(GUARDIAN) {
		uint256 totalShares = bank.totalShares(address(this), 0);
		uint256 yieldTokenAmnt = (shares * _selfBalance(yieldToken)) / totalShares;
		_strategy.redeem(yieldTokenAmnt);
	}

	function closePosition() public onlyRole(GUARDIAN) {
		_strategy.closePosition();
	}

	function underlying() public view returns (IERC20) {
		return _underlying;
	}

	function strategy() public view override returns (address) {
		return address(_strategy);
	}

	// used for estimate only
	function exchangeRateUnderlying() external view returns (uint256) {
		uint256 totalShares = bank.totalShares(address(this), 0);
		if (totalShares == 0) return ONE;
		return
			((_underlying.balanceOf(address(this)) + _strategy.getTotalTVL()) * ONE) / totalShares;
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
		return (AssetType.LIQUIDITY, yieldToken, IERC20Metadata(yieldToken).decimals());
	}

	function underlyingDecimals() public view returns (uint8) {
		return _strategy.decimals();
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
		res[0] = address(_underlying);
	}

	function isValidBaseToken(address token) public view override returns (bool) {
		return token == address(_underlying);
	}

	// send funds to strategy
	function _transferIn(
		address token,
		address from,
		uint256 amount
	) internal override {
		if (token == NATIVE) SafeETH.safeTransferETH(address(_strategy), amount);
		else IERC20(token).safeTransferFrom(from, address(_strategy), amount);
	}

	// send funds to user
	function _transferOut(
		address token,
		address to,
		uint256 amount
	) internal override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransferFrom(address(_strategy), to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(address token) internal view override returns (uint256) {
		return
			(token == NATIVE)
				? address(_strategy).balance
				: IERC20(token).balanceOf(address(_strategy));
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}
}
