// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral, IPoolToken, IBorrowable, ImpermaxChef } from "../../interfaces/imx/IImpermax.sol";
import { HarvestSwapParms, IIMXFarmU, IERC20, SafeERC20, IUniswapV2Pair, IUniswapV2Router01 } from "../mixins/upgradable/IIMXFarmU.sol";
import { UniUtils } from "../../libraries/UniUtils.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { CallType, CalleeData, AddLiquidityAndMintCalldata, BorrowBCalldata, RemoveLiqAndRepayCalldata } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";

abstract contract IMXFarm is Initializable, IIMXFarmU {
	using SafeERC20 for IERC20;
	using UniUtils for IUniswapV2Pair;
	// using FixedPointMathLib for uint256;

	IUniswapV2Pair public _pair;
	ICollateral private _collateralToken;
	IBorrowable private _uBorrowable;
	IBorrowable private _sBorrowable;
	IPoolToken private stakedToken;
	ImpermaxChef private _impermaxChef;

	IERC20 private _farmToken;
	IUniswapV2Router01 private _farmRouter;

	bool public flip;

	function __IMXFarm_init_(
		address underlying_,
		address pair_,
		address collateralToken_,
		address farmRouter_,
		address farmToken_
	) internal onlyInitializing {
		_pair = IUniswapV2Pair(pair_);
		_collateralToken = ICollateral(collateralToken_);
		_uBorrowable = IBorrowable(_collateralToken.borrowable0());
		_sBorrowable = IBorrowable(_collateralToken.borrowable1());
		if (underlying_ != _uBorrowable.underlying()) {
			flip = true;
			(_uBorrowable, _sBorrowable) = (_sBorrowable, _uBorrowable);
		}
		stakedToken = IPoolToken(_collateralToken.underlying());
		_impermaxChef = ImpermaxChef(_uBorrowable.borrowTracker());
		_farmToken = IERC20(farmToken_);
		_farmRouter = IUniswapV2Router01(farmRouter_);

		// necessary farm approvals
		_farmToken.safeApprove(address(farmRouter_), type(uint256).max);
	}

	function impermaxChef() public view override returns (ImpermaxChef) {
		return _impermaxChef;
	}

	function collateralToken() public view override returns (ICollateral) {
		return _collateralToken;
	}

	function sBorrowable() public view override returns (IBorrowable) {
		return _sBorrowable;
	}

	function uBorrowable() public view override returns (IBorrowable) {
		return _uBorrowable;
	}

	function farmRouter() public view override returns (IUniswapV2Router01) {
		return _farmRouter;
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return _pair;
	}

	function _addIMXLiquidity(
		uint256 underlyingAmnt,
		uint256 shortAmnt,
		uint256 uBorrow,
		uint256 sBorrow
	) internal virtual override {
		_sBorrowable.borrowApprove(address(_sBorrowable), sBorrow);

		// mint collateral
		bytes memory addLPData = abi.encode(
			CalleeData({
				callType: CallType.ADD_LIQUIDITY_AND_MINT,
				data: abi.encode(
					AddLiquidityAndMintCalldata({ uAmnt: underlyingAmnt, sAmnt: shortAmnt })
				)
			})
		);

		// borrow short data
		bytes memory borrowSData = abi.encode(
			CalleeData({
				callType: CallType.BORROWB,
				data: abi.encode(BorrowBCalldata({ borrowAmount: uBorrow, data: addLPData }))
			})
		);

		// flashloan borrow then add lp
		_sBorrowable.borrow(address(this), address(this), sBorrow, borrowSData);
	}

	function impermaxBorrow(
		address,
		address,
		uint256,
		bytes calldata data
	) external {
		// ensure that msg.sender is correct
		require(
			msg.sender == address(_sBorrowable) || msg.sender == address(_uBorrowable),
			"IMXFarm: NOT_BORROWABLE"
		);
		CalleeData memory calleeData = abi.decode(data, (CalleeData));

		if (calleeData.callType == CallType.ADD_LIQUIDITY_AND_MINT) {
			AddLiquidityAndMintCalldata memory d = abi.decode(
				calleeData.data,
				(AddLiquidityAndMintCalldata)
			);
			_addLp(d.uAmnt, d.sAmnt);
		} else if (calleeData.callType == CallType.BORROWB) {
			BorrowBCalldata memory d = abi.decode(calleeData.data, (BorrowBCalldata));
			_uBorrowable.borrow(address(this), address(this), d.borrowAmount, d.data);
		}
	}

	function _addLp(uint256 uAmnt, uint256 sAmnt) internal {
		// TODO this block is only used on rebalance
		// use additional param to save gas?
		{
			uint256 sBalance = short().balanceOf(address(this));
			uint256 uBalance = underlying().balanceOf(address(this));

			// if we have extra short tokens, trade them for underlying
			if (sBalance > sAmnt) {
				// TODO edge case - not enough underlying?
				uBalance += pair()._swapExactTokensForTokens(
					sBalance - sAmnt,
					address(short()),
					address(underlying())
				);
			} else if (sAmnt > sBalance) {
				uBalance -= pair()._swapTokensForExactTokens(
					sAmnt - sBalance,
					address(underlying()),
					address(short())
				);
			}
			// we know that now our sBalance = sAmnt
			if (uBalance < uAmnt) {
				uAmnt = uBalance;
				sAmnt = _underlyingToShort(uAmnt);
			} else if (uBalance > uAmnt) {
				underlying().safeTransfer(address(_uBorrowable), uBalance - uAmnt);
			}
		}

		underlying().safeTransfer(address(_pair), uAmnt);
		short().safeTransfer(address(_pair), sAmnt);

		uint256 liquidity = _pair.mint(address(this));

		// first we create staked token, then collateral token
		IERC20(address(_pair)).safeTransfer(address(stakedToken), liquidity);
		stakedToken.mint(address(_collateralToken));
		_collateralToken.mint(address(this));
	}

	function _removeIMXLiquidity(
		uint256 removeLpAmnt,
		uint256 repayUnderlying,
		uint256 repayShort
	) internal override {
		uint256 redeemAmount = (removeLpAmnt * 1e18) / stakedToken.exchangeRate() + 1;

		bytes memory data = abi.encode(
			RemoveLiqAndRepayCalldata({
				removeLpAmnt: removeLpAmnt,
				repayUnderlying: repayUnderlying,
				repayShort: repayShort
			})
		);

		_collateralToken.flashRedeem(address(this), redeemAmount, data);
	}

	function impermaxRedeem(
		address,
		uint256 redeemAmount,
		bytes calldata data
	) external {
		require(msg.sender == address(_collateralToken), "IMXFarm: NOT_COLLATERAL");

		// (uint256 , uint256 shortfall) = _collateralToken.accountLiquidity(address(this));

		RemoveLiqAndRepayCalldata memory d = abi.decode(data, (RemoveLiqAndRepayCalldata));

		// redeem withdrawn staked coins
		IERC20(address(stakedToken)).transfer(address(stakedToken), redeemAmount);
		stakedToken.redeem(address(this));

		// TODO this is not flash-swap safe!!!
		// add slippage param check modifier

		// remove collateral
		(, uint256 shortAmnt) = _removeLiquidity(d.removeLpAmnt);

		// trade extra tokens

		// if we have extra short tokens, trade them for underlying
		if (shortAmnt > d.repayShort) {
			// TODO edge case - not enough underlying?
			pair()._swapExactTokensForTokens(
				shortAmnt - d.repayShort,
				address(short()),
				address(underlying())
			);
			shortAmnt = d.repayShort;
		}
		// if we know the exact amount of short we must repay, then ensure we have that amount
		else if (d.repayShort > shortAmnt && d.repayShort != type(uint256).max) {
			pair()._swapTokensForExactTokens(
				d.repayShort - shortAmnt,
				address(underlying()),
				address(short())
			);
			shortAmnt = d.repayShort;
		}

		uint256 uBalance = underlying().balanceOf(address(this));

		// repay short loan
		short().safeTransfer(address(_sBorrowable), shortAmnt);
		_sBorrowable.borrow(address(this), address(0), 0, new bytes(0));

		// repay underlying loan
		underlying().safeTransfer(
			address(_uBorrowable),
			d.repayUnderlying > uBalance ? uBalance : d.repayUnderlying
		);
		_uBorrowable.borrow(address(this), address(0), 0, new bytes(0));

		uint256 cAmount = (redeemAmount * 1e18) / _collateralToken.exchangeRate() + 1;

		// uint256 colBal = _collateralToken.balanceOf(address(this));
		// TODO add tests to make ensure cAmount < colBal

		// return collateral token
		IERC20(address(_collateralToken)).transfer(
			address(_collateralToken),
			// colBal < cAmount ? colBal : cAmount
			cAmount
		);
	}

	function pendingHarvest() external view override returns (uint256 harvested) {
		harvested =
			_impermaxChef.pendingReward(address(_sBorrowable), address(this)) +
			_impermaxChef.pendingReward(address(_uBorrowable), address(this));
	}

	function _harvestFarm(HarvestSwapParms calldata harvestParams)
		internal
		override
		returns (uint256 harvested)
	{
		address[] memory borrowables = new address[](2);
		borrowables[0] = address(_sBorrowable);
		borrowables[1] = address(_uBorrowable);

		_impermaxChef.massHarvest(borrowables, address(this));

		harvested = _farmToken.balanceOf(address(this));
		if (harvested == 0) return harvested;

		_swap(_farmRouter, harvestParams, address(_farmToken), harvested);
		emit HarvestedToken(address(_farmToken), harvested);
	}

	function _getLiquidity() internal view override returns (uint256) {
		if (_collateralToken.balanceOf(address(this)) == 0) return 0;
		return
			(stakedToken.exchangeRate() *
				(_collateralToken.exchangeRate() *
					(_collateralToken.balanceOf(address(this)) - 1))) /
			1e18 /
			1e18;
	}

	function _getBorrowBalances() internal view override returns (uint256, uint256) {
		return (
			_uBorrowable.borrowBalance(address(this)),
			_sBorrowable.borrowBalance(address(this))
		);
	}

	function accrueInterest() public override {
		_sBorrowable.accrueInterest();
		_uBorrowable.accrueInterest();
	}

	function _updateAndGetBorrowBalances() internal override returns (uint256, uint256) {
		accrueInterest();
		return _getBorrowBalances();
	}

	// borrow amount of underlying for every 1e18 of deposit
	function _optimalUBorrow() internal view override returns (uint256 uBorrow) {
		uint256 l = _collateralToken.liquidationIncentive();
		// this is the adjusted safety margin - how far we stay from liquidation
		uint256 s = (_collateralToken.safetyMarginSqrt() * safetyMarginSqrt()) / 1e18;
		uBorrow = (1e18 * (2e18 - (l * s) / 1e18)) / ((l * 1e18) / s + (l * s) / 1e18 - 2e18);
	}

	// TODO RM - can do this in JS or in tests
	// function getIMXLiquidity() external view returns (uint256 leverage) {
	// 	uint256 collateral = (_collateralToken.exchangeRate() *
	// 		_collateralToken.balanceOf(address(this))) / 1e18;

	// 	uint256 amount0 = _uBorrowable.borrowBalance(address(this));
	// 	uint256 amount1 = _sBorrowable.borrowBalance(address(this));

	// 	(uint256 price0, uint256 price1) = _collateralToken.getPrices();

	// 	uint256 value0 = (amount0 * price0) / 1e18;
	// 	uint256 value1 = (amount1 * price1) / 1e18;
	// 	if (flip) (value0, value1) = (value1, value0);

	// 	leverage = (collateral * 1e18) / (collateral - value0 - value1 + 1);
	// 	console.log("leverage", (collateral * 1e18) / (collateral - value0 - value1 + 1));
	// }
}
