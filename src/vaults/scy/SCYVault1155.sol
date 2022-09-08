// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBase1155, Initializable, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBase1155.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { AuthU } from "../../common/AuthU.sol";
import { FeesU } from "../../common/FeesU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { TreasuryU } from "../../common/TreasuryU.sol";
import { Bank } from "../../bank/Bank.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "hardhat/console.sol";

struct Strategy {
	IMX imx;
	bool exists;
	uint256 strategyId; // this is strategy specific token if 1155
	address yieldToken;
	IERC20 underlying;
	uint128 maxTvl; // pack all params and balances
	uint128 balance; // strategy balance in underlying
	uint128 uBalance; // underlying balance
	uint128 yBalance; // yield token balance
}

contract SCYVault1155 is Initializable, SCYBase1155, FeesU, TreasuryU {
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
		address addr = address(strategy.imx);
		uint256 index = strategyIndexes[addr][strategy.strategyId];
		id = (strategies.length).toUint96();
		if (index < id && strategies[index].exists) revert StrategyExists();
		strategies.push(strategy);
		strategyIndexes[addr][strategy.strategyId] = id;
		emit StrategyUpdated(id, addr);
	}

	/*///////////////////////////////////////////////////////////////
                    CONFIG
    //////////////////////////////////////////////////////////////*/

	function getMaxTvl(uint96 id) public view returns (uint256 maxTvl) {
		Strategy storage strategy = strategies[id];
		return min(strategy.maxTvl, strategy.imx.getMaxTvl());
	}

	function setMaxTvl(uint96 id, uint256 maxTvl) public strategyExists(id) onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		strategy.maxTvl = maxTvl.toUint128();
		emit MaxTvlUpdated(id, min(maxTvl, strategy.imx.getMaxTvl()));
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
		// Strategy storage strategy = strategies[id];
		address yToken = strategy.yieldToken;
		// TODO use stored balance?
		uint256 startYieldToken = _selfBalance(id, yToken);
		strategy.imx.deposit(amount);
		uint256 endYieldToken = _selfBalance(id, yToken);

		amountSharesOut = bank.deposit(
			id,
			receiver,
			endYieldToken - startYieldToken,
			endYieldToken
		);
		strategy.yBalance = endYieldToken.toUint128();
	}

	function _redeem(
		uint96 id,
		address receiver,
		address,
		uint256 sharesToRedeem
	) internal override strategyExists(id) returns (uint256 amountTokenOut) {
		Strategy storage strategy = strategies[id];
		address yToken = strategy.yieldToken;

		uint256 _totalSupply = _selfBalance(id, yToken);
		uint256 yeildTokenAmnt = bank.withdraw(id, receiver, sharesToRedeem, _totalSupply);

		// vault may hold float of underlying, in this case, add a share of reserves to withdrawal
		uint256 reserves = strategy.underlying.balanceOf(address(this));
		uint256 shareOfReserves = (reserves * sharesToRedeem) / _totalSupply;

		amountTokenOut = shareOfReserves + strategy.imx.redeem(yeildTokenAmnt);
	}

	// DoS attack is possible by depositing small amounts of underlying
	// can make it costly by using a maxDust amnt, ex: $100
	// TODO: make sure we don't need check
	function isPaused(uint96 id) public view returns (bool) {
		return strategies[id].underlying.balanceOf(address(this)) > maxDust;
	}

	/// @notice Harvest a set of trusted strategies.
	/// strategiesparam is for backwards compatibility.
	/// @dev Will always revert if called outside of an active
	/// harvest window or before the harvest delay has passed.
	function harvest(uint96 id, address[] calldata) external onlyRole(MANAGER) {
		Strategy storage strategy = strategies[id];
		uint256 tvl = strategy.imx.getAndUpdateTVL();
		uint256 strategyBalance = strategy.balance;
		if (tvl <= strategyBalance) return;

		bank.takeFees(
			id,
			address(this),
			tvl - strategyBalance,
			_selfBalance(id, strategy.yieldToken)
		);
		strategy.balance = tvl.toUint128();
	}

	// TODO: add slippage
	function depositIntoStrategy(uint96 id, uint256 underlyingAmount) public onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		strategy.underlying.safeTransfer(address(strategy.imx), underlyingAmount);
		strategy.imx.deposit(underlyingAmount);
	}

	// TODO: add slippage
	function withdrawFromStrategy(uint96 id, uint256 shares) public onlyRole(GUARDIAN) {
		Strategy storage strategy = strategies[id];
		uint256 totalShares = bank.totalShares(address(this), id);
		uint256 yieldTokenAmnt = (shares * _selfBalance(id, strategy.yieldToken)) / totalShares;
		strategy.imx.redeem(yieldTokenAmnt);
	}

	function closePosition(uint96 id) public onlyRole(GUARDIAN) {
		strategies[id].imx.closePosition();
	}

	function underlying(uint96 id) public view returns (IERC20) {
		return strategies[id].underlying;
	}

	function getStrategy(uint96 id) public view returns (Strategy memory) {
		return strategies[id];
	}

	// used for estimate only
	function exchangeRateUnderlying(uint96 id) external view returns (uint256) {
		Strategy storage strategy = strategies[id];
		uint256 totalShares = bank.totalShares(address(this), id);
		if (totalShares == 0) return ONE;
		return
			((strategy.underlying.balanceOf(address(this)) + strategy.imx.getTotalTVL()) * ONE) /
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
				strategy.imx.getTotalTVL()) * balance) / totalShares;
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
		return strategies[id].imx.decimals();
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
	) internal override {
		if (token == NATIVE) SafeETH.safeTransferETH(address(strategies[id].imx), amount);
		else IERC20(token).safeTransferFrom(from, address(strategies[id].imx), amount);
	}

	// send funds to user
	function _transferOut(
		uint96 id,
		address token,
		address to,
		uint256 amount
	) internal override {
		if (token == NATIVE) {
			SafeETH.safeTransferETH(to, amount);
		} else {
			IERC20(token).safeTransferFrom(address(strategies[id].imx), to, amount);
		}
	}

	// todo handle internal float balances
	function _selfBalance(uint96 id, address token) internal view override returns (uint256) {
		return
			(token == NATIVE)
				? address(strategies[id].imx).balance
				: IERC20(token).balanceOf(address(strategies[id].imx));
	}

	/**
	 * @dev Returns the smallest of two numbers.
	 */
	function min(uint256 a, uint256 b) internal pure returns (uint256) {
		return a < b ? a : b;
	}

	error StrategyExists();
	error StrategyDoesntExist();
}
