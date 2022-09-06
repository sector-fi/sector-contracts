// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import "hardhat/console.sol";

contract SectorTest is Test {
	// using UniUtils for IUniswapV2Pair;

	string private checkpointLabel;
	uint256 private checkpointGasLeft;

	function startMeasuringGas(string memory label) internal virtual {
		checkpointLabel = label;
		checkpointGasLeft = gasleft();
	}

	function stopMeasuringGas() internal virtual {
		uint256 checkpointGasLeft2 = gasleft();

		string memory label = checkpointLabel;

		emit log_named_uint(label, checkpointGasLeft - checkpointGasLeft2);
	}

	function toRangeUint104(
		uint104 input,
		uint256 min,
		uint256 max
	) internal pure returns (uint256 output) {
		output = min + (uint256(input) * (max - min)) / (type(uint104).max);
	}

	function toRange(
		uint128 input,
		uint256 min,
		uint256 max
	) internal pure returns (uint256 output) {
		output = min + (uint256(input) * (max - min)) / (type(uint128).max);
	}

	// used to test IMX Vault
	// function movePrice(
	// 	IUniswapV2Pair pair,
	// 	MockERC20 underlying,
	// 	MockERC20 short,
	// 	uint256 fraction
	// ) internal {
	// 	uint256 adjustUnderlying;
	// 	(uint256 underlyingR, ) = pair._getPairReserves(address(underlying), address(short));
	// 	if (fraction < 1e18) {
	// 		adjustUnderlying = underlyingR - (underlyingR * fraction.sqrt()) / uint256(1e18).sqrt();
	// 		adjustUnderlying = (adjustUnderlying * 9990) / 10000;
	// 		uint256 adjustShort = pair._getAmountIn(
	// 			adjustUnderlying,
	// 			address(short),
	// 			address(underlying)
	// 		);
	// 		short.mint(address(this), adjustShort);
	// 		pair._swapTokensForExactTokens(adjustUnderlying, address(short), address(underlying));
	// 	} else if (fraction > 1e18) {
	// 		adjustUnderlying = (underlyingR * fraction.sqrt()) / uint256(1e18).sqrt() - underlyingR;
	// 		adjustUnderlying = (adjustUnderlying * 10000) / 9990;
	// 		underlying.mint(address(this), adjustUnderlying);
	// 		pair._swapExactTokensForTokens(adjustUnderlying, address(underlying), address(short));
	// 	}
	// }

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
