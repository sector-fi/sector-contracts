// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMXSetup, IUniswapV2Pair } from "./IMXSetup.sol";

import "hardhat/console.sol";

contract IMXUnitTest is IMXSetup {
	function testLoanHealth() public {
		deposit(100e6);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice(maxAdjust);
		assertApproxEqAbs(strategy.loanHealth(), 1e18, 5e14);
	}

	function testLoanHealthRebalance() public {
		deposit(100e6);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice((maxAdjust * 3) / 2);
		rebalance();
	}

	function testLoanHealthWithdraw() public {
		deposit(100e6);
		uint256 maxAdjust = strategy.safetyMarginSqrt()**2 / 1e18;
		adjustPrice(maxAdjust);
		uint256 balance = vault.balanceOf(address(this));
		vm.expectRevert(IMXCore.LowLoanHealth.selector);
		vault.redeem(address(this), (balance * .2e18) / 1e18, address(usdc), 0);
	}

	function testExtremeDivergence() public {
		deposit(100e6);
		adjustPrice(1e18); // set oracle equal to current price

		// only move uniswap price, not oracle
		moveUniswapPrice(
			IUniswapV2Pair(config.uniPair),
			address(config.underlying),
			config.short,
			.8e18
		);

		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		strategy.rebalance(expectedPrice, maxDelta);
		assertGt(strategy.loanHealth(), 1.002e18);
	}

	function testBadRebalanceSlippage() public {}
}
