// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

interface IVeloRouter {
	function weth() external pure returns (address);

	function addLiquidity(
		address tokenA,
		address tokenB,
		bool stable,
		uint256 amountADesired,
		uint256 amountBDesired,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	)
		external
		returns (
			uint256 amountA,
			uint256 amountB,
			uint256 liquidity
		);

	function swapExactTokensForTokensSimple(
		uint256 amountIn,
		uint256 amountOutMin,
		address tokenFrom,
		address tokenTo,
		bool stable,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amounts);
}
