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

import "hardhat/console.sol";

abstract contract levConvexBase is StratAuth, ISCYStrategy {
	using SafeERC20 for IERC20;

	uint256 constant MIN_LIQUIDITY = 10**3;

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
		uint256 withdraw = (uBalance * amount) / startLp;

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
		return withdraw;
	}

	/// @dev manager should be able to lower leverage in case of emergency, but not increase it
	/// increase of leverage can only be done by owner();
	function adjustLeverage(uint16 newLeverage) public onlyRole(MANAGER) {
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
		uint256 currentLeverageFactor = ((100 * totalAssets) / (totalAssets - totalOwed));

		if (currentLeverageFactor > newLeverage) {
			uint256 lp = convexRewardPool.balanceOf(credAcc);
			uint256 repay = (lp * (currentLeverageFactor - newLeverage)) / currentLeverageFactor;
			_decreasePosition(repay);
		} else if (currentLeverageFactor < newLeverage) {
			// we need to increase leverage -> borrow more
			uint256 borrowAmnt = (getAndUpdateTvl() * (newLeverage - currentLeverageFactor)) / 100;
			_increasePosition(borrowAmnt, borrowAmnt);
		}
		/// leverageFactor used for opening & closing accounts
		leverageFactor = uint16(getLeverage()) - 100;
		emit AdjustLeverage(newLeverage);
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
			emit HarvestedToken(address(farmToken), harvested, amountsOut[i]);
		}

		uint256 balance = underlying.balanceOf(credAcc);
		if (balance == 0) (amountsOut, new uint256[](0));

		uint256 borrowAmnt = (balance * leverageFactor) / 100;
		_increasePosition(borrowAmnt, borrowAmnt + balance);
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
			emit HarvestedToken(address(farmToken), harvested, amountsOut[i]);
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
		if (credAcc == address(0)) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets();
		/// this means we're in an upredictable state and should revert
		if (totalOwed > totalAssets) revert BadLoan();
		return ((100 * totalAssets) / (totalAssets - totalOwed));
	}

	function getMaxTvl() public view returns (uint256) {
		(, uint256 maxBorrowed) = creditFacade.limits();
		if (leverageFactor == 0) return maxBorrowed;
		return (100 * maxBorrowed) / leverageFactor;
	}

	/// @dev gearbox accounting is overly concervative so we use calc_withdraw_one_coin
	/// to compute totalAsssets
	function getTvl() public view returns (uint256) {
		if (credAcc == address(0)) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		uint256 totalAssets = getTotalAssets();
		return totalAssets > totalOwed ? totalAssets - totalOwed : 0;
	}

	function getTotalAssets() public view virtual returns (uint256 totalAssets);

	function getAndUpdateTvl() public view returns (uint256) {
		return getTvl();
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
}
