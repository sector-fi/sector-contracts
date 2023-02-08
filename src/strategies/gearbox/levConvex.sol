// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2, MultiCall } from "../../interfaces/gearbox/ICreditFacade.sol";
import { AuthConfig } from "../../common/Auth.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
import { ICurveV1Adapter } from "../../interfaces/gearbox/adapters/ICurveV1Adapter.sol";
import { IBaseRewardPool } from "../../interfaces/gearbox/adapters/IBaseRewardPool.sol";
import { IBooster } from "../../interfaces/gearbox/adapters/IBooster.sol";
import { LevConvexConfig } from "./ILevConvex.sol";
import { levConvexBase } from "./levConvexBase.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

// import "hardhat/console.sol";

contract levConvex is levConvexBase {
	using FixedPointMathLib for uint256;

	ICurveV1Adapter public curveAdapterDeposit;

	constructor(AuthConfig memory authConfig, LevConvexConfig memory config)
		levConvexBase(authConfig, config)
	{
		if (config.curveAdapterDeposit != address(0)) {
			curveAdapterDeposit = ICurveV1Adapter(config.curveAdapterDeposit);
		}
	}

	//// INTERNAL METHODS

	function _increasePosition(uint256 borrowAmnt, uint256 totalAmount) internal override {
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

	function _decreasePosition(uint256 lpAmount) internal override {
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

	function _closePosition() internal override {
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

	function _openAccount(uint256 amount) internal override {
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

	function collateralToUnderlying() public view returns (uint256) {
		uint256 amountOut = curveAdapter.calc_withdraw_one_coin(1e18, int128(uint128(coinId)));
		uint256 currentLeverage = getLeverage();
		return amountOut.mulDivDown(100, currentLeverage);
	}

	function getTotalAssets() public view override returns (uint256 totalAssets) {
		if (credAcc == address(0)) return 0;
		totalAssets = curveAdapter.calc_withdraw_one_coin(
			convexRewardPool.balanceOf(credAcc),
			int128(uint128(coinId))
		);
	}

	/// @dev used to estimate slippage
	function getWithdrawAmnt(uint256 lpAmnt) public view returns (uint256) {
		return
			(100 * curveAdapter.calc_withdraw_one_coin(lpAmnt, int128(uint128(coinId)))) /
			getLeverage();
	}

	/// @dev used to estimate slippage
	function getDepositAmnt(uint256 uAmnt) public view returns (uint256) {
		uint256 amnt = (uAmnt * getLeverage()) / 100;
		if (address(curveAdapterDeposit) != address(0))
			return curveAdapterDeposit.calc_add_one_coin(amnt, int128(uint128(coinId)));
		return curveAdapter.calc_add_one_coin(amnt, int128(uint128(coinId)));
	}
}
