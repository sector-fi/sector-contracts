// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2 } from "../../interfaces/gearbox/ICreditFacade.sol";
import { IPriceOracleV2 } from "../../interfaces/gearbox/IPriceOracleV2.sol";
import { StratAuth } from "../../common/StratAuth.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { ISCYVault } from "../../interfaces/ERC5115/ISCYVault.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurveV1Adapter } from "../../interfaces/gearbox/adapters/ICurveV1Adapter.sol";
import { IBaseRewardPool } from "../../interfaces/gearbox/adapters/IBaseRewardPool.sol";
import { IBooster } from "../../interfaces/gearbox/adapters/IBooster.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
import { BytesLib } from "../../libraries/BytesLib.sol";
import { LevConvexConfig } from "./ILevConvex.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

// import "hardhat/console.sol";

abstract contract levConvexBase is StratAuth, ISCYStrategy {
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	// USDC
	ICreditFacade public immutable creditFacade;
	ICreditManagerV2 public immutable creditManager;
	ISwapRouter public immutable uniswapV3Adapter;
	ICurveV1Adapter public immutable curveAdapter;
	IBaseRewardPool public immutable convexRewardPool;
	IBooster public immutable convexBooster;
	ISwapRouter public immutable farmRouter;

	IERC20 public immutable underlying;

	uint16 immutable convexPid;
	uint16 immutable coinId;

	// leverage factor is how much we borrow in %
	// ex 2x leverage = 100, 3x leverage = 200
	uint16 public leverageFactor;
	address public credAcc; // gearbox credit account // TODO can it expire?

	event SetVault(address indexed vault);

	constructor(AuthConfig memory authConfig, LevConvexConfig memory config) Auth(authConfig) {
		underlying = IERC20(config.underlying);
		leverageFactor = config.leverageFactor;
		creditFacade = ICreditFacade(config.creditFacade);
		creditManager = ICreditManagerV2(creditFacade.creditManager());
		curveAdapter = ICurveV1Adapter(config.curveAdapter);
		convexRewardPool = IBaseRewardPool(config.convexRewardPool);
		convexBooster = IBooster(config.convexBooster);
		convexPid = uint16(convexRewardPool.pid());
		coinId = config.coinId;
		farmRouter = ISwapRouter(config.farmRouter);
		uniswapV3Adapter = ISwapRouter(creditManager.contractToAdapter(address(farmRouter)));
		// do we need granular approvals? or can we just approve once?
		// i.e. what happens after credit account is dilivered to someone else?
		underlying.approve(address(creditManager), type(uint256).max);
	}

	function setVault(address _vault) public onlyOwner {
		if (ISCYVault(_vault).underlying() != underlying) revert WrongVaultUnderlying();
		vault = _vault;
		emit SetVault(vault);
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of underlying to deposit
	function deposit(uint256 amount) public onlyVault returns (uint256) {
		// TODO maxTvl check?
		uint256 startBalance = getLpBalance();
		if (credAcc == address(0)) _openAccount(amount);
		else {
			uint256 borrowAmnt = (amount * (leverageFactor)) / 100;
			creditFacade.addCollateral(address(this), address(underlying), amount);
			_increasePosition(borrowAmnt, borrowAmnt + amount);
		}
		emit Deposit(msg.sender, amount);
		// our balance should allays increase on deposits
		// adjust the collateralBalance by leverage amount
		return (getLpBalance() - startBalance);
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of lp to withdraw
	function redeem(address to, uint256 amount) public onlyVault returns (uint256) {
		/// there is no way to partially withdraw collateral
		/// we have to close account and re-open it :\
		uint256 startLp = getLpBalance();
		_closePosition();
		uint256 uBalance = underlying.balanceOf(address(this));
		uint256 withdraw = uBalance.mulDivDown(amount, startLp);

		(uint256 minBorrowed, ) = creditFacade.limits();
		uint256 minUnderlying = leverageFactor == 0
			? minBorrowed
			: (100 * minBorrowed) / leverageFactor;
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
		// note we are returning the amount that is equivalent to the amount of LP tokens
		// requested to be redeemed, this may not be the same as the total amount of underlying transferred
		// the vault accounting logic needs to handle this case correctly
		return withdraw;
	}

	/// @dev manager should be able to lower leverage in case of emergency, but not increase it
	/// increase of leverage can only be done by owner();
	function adjustLeverage(
		uint256 expectedTvl,
		uint256 maxDelta,
		uint16 newLeverage
	) public onlyRole(MANAGER) {
		if (msg.sender != owner && newLeverage > leverageFactor + 100)
			revert IncreaseLeveragePermissions();

		if (credAcc == address(0)) {
			leverageFactor = newLeverage - 100;
			emit AdjustLeverage(newLeverage);
			return;
		}

		uint256 totalAssets = getTotalAssets();
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);

		if (totalOwed > totalAssets) revert BadLoan();
		uint256 tvl = (totalAssets - totalOwed);
		_checkSlippage(expectedTvl, tvl, maxDelta);

		uint256 currentLeverage = totalAssets.mulDivDown(100, tvl);

		if (currentLeverage > newLeverage) {
			uint256 lp = convexRewardPool.balanceOf(credAcc);
			uint256 repay = lp.mulDivDown(currentLeverage - newLeverage, currentLeverage);
			_decreasePosition(repay);
		} else if (currentLeverage < newLeverage) {
			// we need to increase leverage -> borrow more
			uint256 borrowAmnt = (getAndUpdateTvl() * (newLeverage - currentLeverage)) / 100;
			_increasePosition(borrowAmnt, borrowAmnt);
		}
		/// leverageFactor used for opening & closing accounts
		leverageFactor = uint16(getLeverage()) - 100;
		emit AdjustLeverage(newLeverage);
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

	function harvest(HarvestSwapParams[] memory swapParams, HarvestSwapParams[] memory)
		public
		onlyVault
		returns (uint256[] memory amountsOut, uint256[] memory)
	{
		if (credAcc == address(0)) return _harvestOwnTokens(swapParams);

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
			emit HarvestedToken(address(token), harvested, amountsOut[i]);
		}

		uint256 balance = underlying.balanceOf(credAcc);
		if (balance == 0) (amountsOut, new uint256[](0));

		uint256 borrowAmnt = (balance * leverageFactor) / 100;
		(, uint256 maxBorrow) = creditFacade.limits();
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		if (totalOwed + balance <= maxBorrow) _increasePosition(borrowAmnt, borrowAmnt + balance);

		return (amountsOut, new uint256[](0));
	}

	// method to harvest if we have closed the credit account
	function _harvestOwnTokens(HarvestSwapParams[] memory swapParams)
		internal
		returns (uint256[] memory amountsOut, uint256[] memory)
	{
		amountsOut = new uint256[](swapParams.length);
		for (uint256 i; i < swapParams.length; ++i) {
			IERC20 token = IERC20(BytesLib.toAddress(swapParams[i].pathData, 0));
			uint256 harvested = token.balanceOf(address(this));
			if (harvested == 0) continue;
			if (token.allowance(address(this), address(farmRouter)) < harvested)
				token.safeApprove(address(farmRouter), type(uint256).max);
			ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
				path: swapParams[i].pathData,
				recipient: address(this),
				deadline: block.timestamp,
				amountIn: harvested,
				amountOutMinimum: swapParams[i].min
			});
			amountsOut[i] = farmRouter.exactInput(params);
			emit HarvestedToken(address(token), harvested, amountsOut[i]);
		}
		uint256 balance = underlying.balanceOf(address(this));
		underlying.safeTransfer(vault, balance);
		return (amountsOut, new uint256[](0));
	}

	function closePosition(uint256) public onlyVault returns (uint256) {
		// withdraw all rewards
		convexRewardPool.getReward();
		_closePosition();
		credAcc = address(0);
		uint256 balance = underlying.balanceOf(address(this));
		underlying.safeTransfer(vault, balance);
		return balance;
	}

	//// INTERNAL METHODS

	function _increasePosition(uint256 borrowAmnt, uint256 totalAmount) internal virtual;

	function _decreasePosition(uint256 lpAmount) internal virtual;

	function _closePosition() internal virtual;

	function _openAccount(uint256 amount) internal virtual;

	/// VIEW METHODS

	function loanHealth() public view returns (uint256) {
		// if account is closed our health is 1000%
		if (credAcc == address(0)) return 100e18;
		// gearbox returns basis points, we convert it to 10,000 => 100% => 1e18
		return 1e14 * creditFacade.calcCreditAccountHealthFactor(credAcc);
	}

	function getLeverage() public view returns (uint256) {
		if (credAcc == address(0)) return leverageFactor + 100;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets();
		/// this means we're in an upredictable state and should revert
		if (totalOwed > totalAssets) revert BadLoan();
		return totalAssets.mulDivDown(100, totalAssets - totalOwed);
	}

	function getMaxTvl() public view returns (uint256) {
		(, uint256 maxBorrowed) = creditFacade.limits();
		if (leverageFactor == 0) return maxBorrowed;
		return (100 * maxBorrowed) / leverageFactor;
	}

	/// @dev gearbox accounting is overly concervative so
	/// we use calc_withdraw_one_coin to compute totalAsssets
	function getTvl() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets() + underlying.balanceOf(credAcc);
		return totalAssets > totalOwed ? totalAssets - totalOwed : 0;
	}

	function getTotalAssets() public view virtual returns (uint256 totalAssets);

	function getAndUpdateTvl() public view returns (uint256) {
		return getTvl();
	}

	function getLpToken() public view returns (address) {
		return address(convexRewardPool);
	}

	function getLpBalance() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		return convexRewardPool.balanceOf(credAcc);
	}

	event AdjustLeverage(uint256 newLeverage);
	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);
	event Deposit(address sender, uint256 amount);
	event Redeem(address sender, uint256 amount);

	error BadLoan();
	error IncreaseLeveragePermissions();
	error WrongVaultUnderlying();
	error SlippageExceeded();
}
