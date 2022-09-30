// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IMXSetup } from "./IMXSetup.sol";

import "hardhat/console.sol";

contract IMXIntegrationTest is IMXSetup {
	function testIntegrationFlow() public {
		deposit(100e6);
		noRebalance();
		withdrawCheck(.5e18);
		deposit(100e6);
		harvest();
		adjustPrice(0.9e18);
		strategy.getAndUpdateTVL();
		rebalance();
		adjustPrice(1.2e18);
		rebalance();
		withdrawAll();
	}

	function testAccounting() public {
		uint256 amnt = 1000e6;
		vm.startPrank(address(2));
		deposit(amnt, address(2));
		vm.stopPrank();
		adjustPrice(1.2e18);
		deposit(amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(address(this)),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		adjustPrice(.833e18);
		uint256 balance = vault.underlyingBalance(address(2));
		assertGt(balance, amnt, "first balance should not decrease"); // within .1%
	}

	function testFlashSwap() public {
		uint256 amnt = 1000e6;
		vm.startPrank(address(2));
		deposit(amnt, address(2));
		vm.stopPrank();
		// trackCost();
		moveUniPrice(1.5e18);
		deposit(amnt);
		assertApproxEqAbs(
			vault.underlyingBalance(address(this)),
			amnt,
			(amnt * 3) / 1000, // withthin .003% (slippage)
			"second balance"
		);
		moveUniPrice(.666e18);
		uint256 balance = vault.underlyingBalance(address(2));
		assertGt(balance, amnt, "first balance should not decrease"); // within .1%
	}

	function noRebalance() public {
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		vm.expectRevert(IMXCore.RebalanceThreshold.selector);
		strategy.rebalance(expectedPrice, maxDelta);
	}

	function withdrawCheck(uint256 fraction) public {
		uint256 startTvl = strategy.getTotalTVL();
		withdraw(fraction);

		uint256 tvl = strategy.getTotalTVL();
		assertApproxEqAbs(tvl, (startTvl * (1e18 - fraction)) / 1e18, 10);
		assertApproxEqAbs(vault.underlyingBalance(address(this)), tvl, 10);
	}

	function harvest() public {
		vm.warp(block.timestamp + 1 * 60 * 60 * 24);
		address[] memory path = new address[](3);
		path[0] = 0xeA6887e4a9CdA1B77E70129E5Fba830CdB5cdDef;
		path[1] = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
		path[2] = 0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664;
		harvestParams.path = path;
		harvestParams.min = 0;
		harvestParams.deadline = block.timestamp + 1;
		strategy.getAndUpdateTVL();
		uint256 tvl = strategy.getTotalTVL();
		uint256 harvestAmnt = strategy.harvest(harvestParams);
		uint256 newTvl = strategy.getTotalTVL();
		assertGt(harvestAmnt, 0);
		assertGt(newTvl, tvl);
	}

	function withdrawAll() public {
		uint256 balance = vault.balanceOf(address(this));

		vault.redeem(address(this), balance, address(underlying), 0);

		uint256 tvl = strategy.getTotalTVL();
		assertEq(tvl, 0);
		assertEq(vault.balanceOf(address(this)), 0);
		assertEq(vault.underlyingBalance(address(this)), 0);
	}
}
