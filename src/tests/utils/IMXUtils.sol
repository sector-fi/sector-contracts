// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "../mocks/MockERC20.sol";
import { UniUtils, IUniswapV2Pair } from "../../libraries/UniUtils.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { UQ112x112 } from "../utils/UQ112x112.sol";

abstract contract IMXUtils is Test {
	using UniUtils for IUniswapV2Pair;
	using FixedPointMathLib for uint256;
	using UQ112x112 for uint112;
	using UQ112x112 for uint224;

	function mockOraclePrice(
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
		} else if (fraction > 1e18) {
			adjustUnderlying = (underlyingR * fraction.sqrt()) / uint256(1e18).sqrt() - underlyingR;
			adjustUnderlying = (adjustUnderlying * 10000) / 9990;
			deal(underlying, address(this), adjustUnderlying);
			pair._swapExactTokensForTokens(adjustUnderlying, underlying, short);
		}
	}

	function movePrice(
		address _pair,
		address underlying,
		address short,
		address oracle,
		uint256 fraction
	) public {
		IUniswapV2Pair pair = IUniswapV2Pair(_pair);
		moveUniswapPrice(pair, underlying, short, fraction);
		(uint256 uR, uint256 sR) = pair._getPairReserves(underlying, short);
		uint224 price = uint112(uR).encode().uqdiv(uint112(sR));
		mockOraclePrice(oracle, _pair, price);
	}

	// function logTvl(HedgedLP strategy) internal view {
	// 	(
	// 		uint256 tvl,
	// 		uint256 collateralBalance,
	// 		uint256 shortPosition,
	// 		uint256 borrowBalance,
	// 		uint256 lpBalance,
	// 		uint256 underlyingBalance
	// 	) = strategy.getTVL();
	// 	console.log("tvl", tvl);
	// 	console.log("collateralBalance", collateralBalance);
	// 	console.log("shortPosition", shortPosition);
	// 	console.log("borrowBalance", borrowBalance);
	// 	console.log("lpBalance", lpBalance);
	// 	console.log("underlyingBalance", underlyingBalance);
	// }
}
