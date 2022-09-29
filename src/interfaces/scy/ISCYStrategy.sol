// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISCYStrategy {
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountTokenToPull,
		uint256 minSharesOut
	) external payable returns (uint256 amountSharesOut);

	function redeem(
		address receiver,
		uint256 amountSharesToPull,
		address tokenOut,
		uint256 minTokenOut
	) external returns (uint256 amountTokenOut);

	function underlying() external view returns (IERC20);

	function strategy() external view returns (address);

	function getAndUpdateTvl() external returns (uint256 tvl);

	function getTvl() external returns (uint256 tvl);
}
