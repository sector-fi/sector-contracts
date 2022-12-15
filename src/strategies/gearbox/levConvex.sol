// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2, MultiCall } from "interfaces/gearbox/ICreditFacade.sol";
import { IPriceOracleV2 } from "../../interfaces/gearbox/IPriceOracleV2.sol";
import { StratAuth } from "../../common/StratAuth.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ICurvePool } from "../../interfaces/curve/ICurvePool.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
import { ICurveV1Adapter } from "../../interfaces/gearbox/adapters/ICurveV1Adapter.sol";
import { IBaseRewardPool } from "../../interfaces/gearbox/adapters/IBaseRewardPool.sol";
import { IBooster } from "../../interfaces/gearbox/adapters/IBooster.sol";

import "hardhat/console.sol";

struct LevConvexConfig {
	address curveAdapter;
	address convexRewardPool;
	address creditFacade;
	uint16 coinId;
	address underlying;
	uint16 leverageFactor;
	address convexBooster;
}

contract levConvex is StratAuth {
	using SafeERC20 for IERC20;

	// USDC
	ICreditFacade public creditFacade;
	//  = ICreditFacade(0x61fbb350e39cc7bF22C01A469cf03085774184aa);

	ICreditManagerV2 public creditManager; // = ICreditManagerV2(creditFacade.creditManager());

	IPriceOracleV2 public priceOracle = IPriceOracleV2(0x6385892aCB085eaa24b745a712C9e682d80FF681);

	ICurveV1Adapter public curveAdapter;
	IBaseRewardPool public convexRewardPool;
	IBooster public convexBooster;

	IERC20 public immutable underlying;

	uint16 convexPid;
	bool hasOpenAccount;
	// leverage factor is how much we borrow in %
	// ex 2x leverage = 100, 3x leverage = 200
	uint16 public leverageFactor;
	uint256 immutable dec;
	uint256 constant shortDec = 1e18;
	address credAcc; // gearbox credit account // TODO can it expire?
	uint16 coinId;

	event SetVault(address indexed vault);

	constructor(AuthConfig memory authConfig, LevConvexConfig memory config) Auth(authConfig) {
		underlying = IERC20(config.underlying);
		dec = 10**uint256(IERC20Metadata(address(underlying)).decimals());
		leverageFactor = config.leverageFactor;
		creditFacade = ICreditFacade(config.creditFacade);
		creditManager = ICreditManagerV2(creditFacade.creditManager());
		curveAdapter = ICurveV1Adapter(config.curveAdapter);
		convexRewardPool = IBaseRewardPool(config.convexRewardPool);
		convexBooster = IBooster(config.convexBooster);
		convexPid = uint16(convexRewardPool.pid());
		coinId = config.coinId;

		// do we need granular approvals? or can we just approve once?
		// i.e. what happens after credit account is dilivered to someone else?
		underlying.approve(address(creditManager), type(uint256).max);
	}

	function setVault(address _vault) public onlyOwner {
		if (ISCYStrategy(_vault).underlying() != underlying) revert WrongVaultUnderlying();
		vault = _vault;
		emit SetVault(vault);
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of underlying to deposit
	function deposit(uint256 amount) public onlyVault returns (uint256) {
		if (!hasOpenAccount) _openAccount(amount);
		else {
			uint256 borrowAmnt = (amount * leverageFactor) / 100;
			creditFacade.addCollateral(address(this), address(underlying), amount);
			creditFacade.increaseDebt(borrowAmnt);
		}
		uint256 startBalance = collateralBalance();
		_increasePosition();
		// our balance should allays increase on deposits
		return collateralBalance() - startBalance;
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of lp to withdraw
	function redeem(uint256 amount, address to) public onlyVault returns (uint256) {
		/// there is no way to partially withdraw collateral
		/// we have to close account and re-open it :\
		uint256 startLp = _closePosition();
		uint256 uBalance = underlying.balanceOf(address(this));
		uint256 withdraw = (uBalance * amount) / startLp;

		(uint256 minBorrowed, ) = creditFacade.limits();
		uint256 minUnderlying = minBorrowed / leverageFactor;
		uint256 redeposit = uBalance > withdraw ? uBalance - withdraw : 0;

		// TODO handle how to deal with leftover underlying
		// return to SCY vault, but allow deposits?
		if (redeposit > minUnderlying) {
			console.log("re open", redeposit);
			_openAccount(uBalance - withdraw);
		}
		underlying.safeTransfer(to, withdraw);
		return withdraw;
	}

	function _increasePosition() internal {
		uint256 balance = underlying.balanceOf(credAcc);

		MultiCall[] memory calls = new MultiCall[](2);
		calls[0] = MultiCall({
			target: address(curveAdapter),
			callData: abi.encodeWithSelector(
				ICurveV1Adapter.add_liquidity_one_coin.selector,
				balance,
				coinId,
				0 // slippage parameter is checked in the vault
			)
		});
		calls[1] = MultiCall({
			target: address(convexBooster),
			callData: abi.encodeWithSelector(IBooster.depositAll.selector, convexPid, true)
		});
		creditFacade.multicall(calls);
	}

	function closePosition() public onlyVault returns (uint256) {
		_closePosition();
		uint256 balance = underlying.balanceOf(address(this));
		underlying.safeTransfer(vault, balance);
		return balance;
	}

	/// return original stETH balance
	function _closePosition() internal returns (uint256) {
		uint256 startBalance = collateralBalance();

		MultiCall[] memory calls;
		calls = new MultiCall[](2);
		calls[0] = MultiCall({
			target: address(convexRewardPool),
			callData: abi.encodeWithSelector(IBaseRewardPool.withdrawAllAndUnwrap.selector, true)
		});

		// convert extra eth to underlying
		calls[1] = MultiCall({
			target: address(curveAdapter),
			callData: abi.encodeWithSelector(
				ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
				coinId,
				0 // slippage is checked in the vault
			)
		});

		creditFacade.closeCreditAccount(address(this), 0, false, calls);
		return startBalance;
	}

	function _openAccount(uint256 amount) internal {
		underlying.approve(address(creditManager), amount);

		// todo oracle conversion from underlying to ETH
		uint256 borrowAmnt = (amount * leverageFactor) / 100;

		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(
				ICreditFacade.addCollateral.selector,
				address(this),
				underlying,
				amount
			)
		});

		creditFacade.openCreditAccountMulticall(borrowAmnt, address(this), calls, 0);
		credAcc = creditManager.getCreditAccountOrRevert(address(this));
		hasOpenAccount = true;
	}

	function loanHealth() public view returns (uint256) {
		console.log("lt", creditManager.liquidationThresholds(address(curveAdapter.lp_token())));
		return creditFacade.calcCreditAccountHealthFactor(credAcc);
	}

	function getMaxTvl() public view returns (uint256) {
		(, uint256 maxBorrowed) = creditFacade.limits();
		return (100 * maxBorrowed) / leverageFactor;
	}

	function collateralToUnderlying() public view returns (uint256) {
		uint256 amountOut = curveAdapter.calc_withdraw_one_coin(1e18, int128(uint128(coinId)));
		return amountOut;
	}

	function collateralBalance() public view returns (uint256) {
		return convexRewardPool.balanceOf(credAcc);
	}

	function getTotalTVL() public view returns (uint256) {
		if (!hasOpenAccount) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		(uint256 totalAssets, ) = creditFacade.calcTotalValue(credAcc);
		if (totalOwed > totalAssets) return 0;
		return totalAssets - totalOwed;
	}

	function getAndUpdateTVL() public view returns (uint256) {
		return getTotalTVL();
	}

	error WrongVaultUnderlying();
}
