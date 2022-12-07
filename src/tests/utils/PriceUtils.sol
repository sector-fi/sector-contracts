// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../mocks/MockERC20.sol";
import { UniUtils, IUniswapV2Pair } from "../../libraries/UniUtils.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { UQ112x112 } from "../utils/UQ112x112.sol";
import { ICompPriceOracle } from "interfaces/compound/ICompPriceOracle.sol";

import "hardhat/console.sol";

abstract contract PriceUtils is Test {
	using UniUtils for IUniswapV2Pair;
	using FixedPointMathLib for uint256;
	using UQ112x112 for uint112;
	using UQ112x112 for uint224;

	struct FlashCost {
		uint256 u;
		uint256 s;
		uint256 uDebt;
		uint256 sDebt;
	}
	FlashCost flashCost;

	function trackCost() public {
		flashCost.u = 0;
		flashCost.s = 0;
		flashCost.uDebt = 0;
		flashCost.sDebt = 0;
	}

	function updateFlashCost(
		uint256 u,
		uint256 s,
		uint256 uDebt,
		uint256 sDebt
	) public {
		flashCost.u += u;
		flashCost.s += s;
		flashCost.uDebt += uDebt;
		flashCost.sDebt += sDebt;
		if (flashCost.u > flashCost.uDebt) {
			flashCost.u -= flashCost.uDebt;
			flashCost.uDebt = 0;
		} else {
			flashCost.uDebt -= flashCost.u;
			flashCost.u = 0;
		}

		if (flashCost.s > flashCost.sDebt) {
			flashCost.s -= flashCost.sDebt;
			flashCost.sDebt = 0;
		} else {
			flashCost.sDebt -= flashCost.s;
			flashCost.s = 0;
		}
	}

	function moveUniswapPrice(
		IUniswapV2Pair pair,
		address underlying,
		address short,
		uint256 fraction
	) internal {
		uint256 adjustUnderlying;
		(uint256 underlyingR, ) = pair._getPairReserves(underlying, short);
		if (fraction < 1e18) {
			adjustUnderlying = underlyingR - (underlyingR * fraction.sqrt()) / uint256(1e18).sqrt();
			adjustUnderlying = (adjustUnderlying * 9990) / 10000;
			uint256 adjustShort = pair._getAmountIn(adjustUnderlying, short, underlying);
			deal(short, address(this), adjustShort);
			pair._swapTokensForExactTokens(adjustUnderlying, short, underlying);
			updateFlashCost(adjustUnderlying, 0, 0, adjustShort);
		} else if (fraction > 1e18) {
			adjustUnderlying = (underlyingR * fraction.sqrt()) / uint256(1e18).sqrt() - underlyingR;
			adjustUnderlying = (adjustUnderlying * 10000) / 9990;
			deal(underlying, address(this), adjustUnderlying);
			uint256 shortAmnt = pair._swapExactTokensForTokens(adjustUnderlying, underlying, short);
			updateFlashCost(0, shortAmnt, adjustUnderlying, 0);
		}
	}

	function mockImxOraclePrice(
		address oracle,
		address pair,
		uint224 price
	) public {
		vm.mockCall(
			oracle,
			abi.encodeWithSelector(ISimpleUniswapOracle.getResult.selector, pair),
			abi.encode(price, 360)
		);
	}

	function mockHlpOraclePrice(
		address oracle,
		address cToken,
		uint256 price
	) public {
		vm.mockCall(
			oracle,
			abi.encodeWithSelector(ICompPriceOracle.getUnderlyingPrice.selector, cToken),
			abi.encode(price)
		);
	}

	function moveImxPrice(
		address _pair,
		address stakedToken,
		address underlying,
		address short,
		address oracle,
		uint256 fraction
	) public {
		IUniswapV2Pair pair = IUniswapV2Pair(_pair);
		(uint112 r0, uint112 r1, ) = IUniswapV2Pair(stakedToken).getReserves();
		moveUniswapPrice(pair, underlying, short, fraction);
		(uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(stakedToken).getReserves();
		uint224 price = uint112(reserve1).encode().uqdiv(uint112(reserve0));
		mockImxOraclePrice(oracle, stakedToken, price);
	}

	function moveHlpPrice(
		address _pair,
		address cToken,
		address underlying,
		address short,
		address oracle,
		uint256 fraction
	) public {
		IUniswapV2Pair pair = IUniswapV2Pair(_pair);
		moveUniswapPrice(pair, underlying, short, fraction);
		uint256 price = (fraction * ICompPriceOracle(oracle).getUnderlyingPrice(cToken)) / 1e18;
		mockHlpOraclePrice(oracle, cToken, price);
	}
}
