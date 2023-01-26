// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2, MultiCall } from "../../interfaces/gearbox/ICreditFacade.sol";
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
import { EAction, HarvestSwapParams } from "../../interfaces/Structs.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
import { BytesLib } from "../../libraries/BytesLib.sol";
import { LevConvexConfig } from "./ILevConvex.sol";

// import "hardhat/console.sol";

contract levConvex is StratAuth {
	using SafeERC20 for IERC20;

	// USDC
	ICreditFacade public creditFacade;

	ICreditManagerV2 public creditManager;

	IPriceOracleV2 public priceOracle = IPriceOracleV2(0x6385892aCB085eaa24b745a712C9e682d80FF681);

	ISwapRouter public uniswapV3Adapter;

	ICurveV1Adapter public curveAdapter;
	ICurveV1Adapter public threePoolAdapter =
		ICurveV1Adapter(0xbd871de345b2408f48C1B249a1dac7E0D7D4F8f9);
	IBaseRewardPool public convexRewardPool;
	IBooster public convexBooster;
	ISwapRouter public farmRouter;

	IERC20 public farmToken;
	IERC20 public immutable underlying;

	uint16 convexPid;
	// leverage factor is how much we borrow in %
	// ex 2x leverage = 100, 3x leverage = 200
	uint16 public leverageFactor;
	uint256 immutable dec;
	uint256 constant shortDec = 1e18;
	address public credAcc; // gearbox credit account // TODO can it expire?
	uint16 coinId;
	bool threePool = true;

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
		farmToken = IERC20(convexRewardPool.rewardToken());
		farmRouter = ISwapRouter(config.farmRouter);
		uniswapV3Adapter = ISwapRouter(creditManager.contractToAdapter(address(farmRouter)));
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
		// TODO maxTvl check?
		uint256 startBalance = collateralBalance();
		if (credAcc == address(0)) _openAccount(amount);
		else {
			uint256 borrowAmnt = (amount * (leverageFactor)) / 100;
			creditFacade.addCollateral(address(this), address(underlying), amount);
			_increasePosition(borrowAmnt, borrowAmnt + amount);
		}
		emit Deposit(msg.sender, amount);
		// our balance should allays increase on deposits
		// adjust the collateralBalance by leverage amount
		return (collateralBalance() - startBalance);
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of lp to withdraw
	function redeem(uint256 amount, address to) public onlyVault returns (uint256) {
		/// there is no way to partially withdraw collateral
		/// we have to close account and re-open it :\
		uint256 startLp = collateralBalance();
		_closePosition();
		uint256 uBalance = underlying.balanceOf(address(this));
		uint256 withdraw = (uBalance * amount) / startLp;

		(uint256 minBorrowed, ) = creditFacade.limits();
		uint256 minUnderlying = (100 * minBorrowed) / leverageFactor;
		uint256 redeposit = uBalance > withdraw ? uBalance - withdraw : 0;

		if (redeposit > minUnderlying) {
			underlying.safeTransfer(to, withdraw);
			_openAccount(redeposit);
		} else {
			// do not re-open account
			credAcc = address(0);
			// send full balance to vault
			underlying.safeTransfer(to, uBalance);
		}

		emit Redeem(msg.sender, amount);
		return withdraw;
	}

	function adjustLeverage(uint16 newLeverageFactor) public onlyRole(MANAGER) {
		if (credAcc == address(0)) {
			leverageFactor = newLeverageFactor - 100;
			emit AdjustLeverage(newLeverageFactor);
			return;
		}

		uint256 totalAssets = getTotalAssets();
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);

		// if (totalOwed > totalAssets) return 0;
		uint256 currentLeverageFactor = ((100 * totalAssets) / (totalAssets - totalOwed));

		if (currentLeverageFactor > newLeverageFactor) {
			uint256 lp = convexRewardPool.balanceOf(credAcc);
			uint256 repay = (lp * (currentLeverageFactor - newLeverageFactor)) /
				currentLeverageFactor;
			_decreasePosition(repay);
			// uint256 balance = underlying.balanceOf(credAcc);
			// creditFacade.decreaseDebt(balance);
		} else if (currentLeverageFactor < newLeverageFactor) {
			// we need to increase leverage
			// we need to borrow more
			uint256 borrowAmnt = (getAndUpdateTVL() * (newLeverageFactor - currentLeverageFactor)) /
				100;
			_increasePosition(borrowAmnt, borrowAmnt);
		}
		/// leverageFactor used for opening & closing accounts
		leverageFactor = uint16(getLeverage()) - 100;
		emit AdjustLeverage(newLeverageFactor);
	}

	function harvest(HarvestSwapParams[] memory swapParams)
		public
		onlyVault
		returns (uint256[] memory amountsOut)
	{
		convexRewardPool.getReward();
		amountsOut = new uint256[](swapParams.length);
		for (uint256 i; i < swapParams.length; ++i) {
			IERC20 token = IERC20(BytesLib.toAddress(swapParams[i].pathData, 0));
			uint256 harvested = token.balanceOf(credAcc);
			if (harvested == 0) continue;
			ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
				path: swapParams[i].pathData,
				recipient: address(this),
				deadline: block.timestamp,
				amountIn: harvested,
				amountOutMinimum: swapParams[i].min
			});
			amountsOut[i] = uniswapV3Adapter.exactInput(params);
			emit HarvestedToken(address(farmToken), harvested, amountsOut[i]);
		}

		uint256 balance = underlying.balanceOf(credAcc);
		uint256 correntLeverageFactor = getLeverage() - 100;
		uint256 borrowAmnt = (balance * correntLeverageFactor) / 100;
		_increasePosition(borrowAmnt, borrowAmnt + balance);
	}

	function closePosition() public onlyVault returns (uint256) {
		_closePosition();
		credAcc = address(0);
		uint256 balance = underlying.balanceOf(address(this));
		underlying.safeTransfer(vault, balance);
		return balance;
	}

	//// INTERNAL METHODS

	function _increasePosition(uint256 borrowAmnt, uint256 totalAmount) internal {
		MultiCall[] memory calls = new MultiCall[](3);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, borrowAmnt)
		});
		calls[1] = MultiCall({
			target: address(curveAdapter),
			callData: abi.encodeWithSelector(
				ICurveV1Adapter.add_liquidity_one_coin.selector,
				totalAmount,
				coinId,
				0 // slippage parameter is checked in the vault
			)
		});
		calls[2] = MultiCall({
			target: address(convexBooster),
			callData: abi.encodeWithSelector(IBooster.depositAll.selector, convexPid, true)
		});
		creditFacade.multicall(calls);
	}

	function _decreasePosition(uint256 lpAmount) internal {
		uint256 repayAmnt = curveAdapter.calc_withdraw_one_coin(lpAmount, int128(uint128(coinId)));
		MultiCall[] memory calls = new MultiCall[](3);
		calls[0] = MultiCall({
			target: address(convexRewardPool),
			callData: abi.encodeWithSelector(
				IBaseRewardPool.withdrawAndUnwrap.selector,
				lpAmount,
				false
			)
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

		calls[2] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, repayAmnt)
		});

		creditFacade.multicall(calls);
	}

	function _closePosition() internal {
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
	}

	function _openAccount(uint256 amount) internal {
		// todo oracle conversion from underlying to ETH
		uint256 borrowAmnt = (amount * leverageFactor) / 100;

		MultiCall[] memory calls = new MultiCall[](3);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(
				ICreditFacade.addCollateral.selector,
				address(this),
				underlying,
				amount
			)
		});
		calls[1] = MultiCall({
			target: address(curveAdapter),
			callData: abi.encodeWithSelector(
				ICurveV1Adapter.add_liquidity_one_coin.selector,
				borrowAmnt + amount,
				coinId,
				0 // slippage parameter is checked in the vault
			)
		});
		calls[2] = MultiCall({
			target: address(convexBooster),
			callData: abi.encodeWithSelector(IBooster.depositAll.selector, convexPid, true)
		});

		creditFacade.openCreditAccountMulticall(borrowAmnt, address(this), calls, 0);
		credAcc = creditManager.getCreditAccountOrRevert(address(this));
	}

	/// VIEW METHODS

	function loanHealth() public view returns (uint256) {
		// gearbox returns basis points, we convert it to 10,000 => 100% => 1e18
		return 1e14 * creditFacade.calcCreditAccountHealthFactor(credAcc);
	}

	function getLeverage() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets();
		if (totalOwed > totalAssets) return 0;
		return ((100 * totalAssets) / (totalAssets - totalOwed));
	}

	function getMaxTvl() public view returns (uint256) {
		(, uint256 maxBorrowed) = creditFacade.limits();
		return (100 * maxBorrowed) / leverageFactor;
	}

	// this is actually not totally accurate
	function collateralToUnderlying() public view returns (uint256) {
		uint256 amountOut = curveAdapter.calc_withdraw_one_coin(1e18, int128(uint128(coinId)));
		uint256 currentLeverage = getLeverage();
		if (currentLeverage == 0) return (100 * amountOut) / (leverageFactor + 100);
		return (100 * amountOut) / currentLeverage;
	}

	function collateralBalance() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		return convexRewardPool.balanceOf(credAcc);
	}

	/// @dev gearbox accounting is overly concervative so we use calc_withdraw_one_coin
	/// to compute totalAsssets
	function getTotalTVL() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets();
		return totalAssets > totalOwed ? totalAssets - totalOwed : 0;
	}

	function getTotalAssets() public view returns (uint256 totalAssets) {
		totalAssets = curveAdapter.calc_withdraw_one_coin(
			convexRewardPool.balanceOf(credAcc),
			int128(uint128(coinId))
		);
	}

	function getAndUpdateTVL() public view returns (uint256) {
		return getTotalTVL();
	}

	event AdjustLeverage(uint256 newLeverage);
	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);
	event Deposit(address sender, uint256 amount);
	event Redeem(address sender, uint256 amount);

	error WrongVaultUnderlying();
}
