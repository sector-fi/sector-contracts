// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { levConvexSetup, SCYStratUtils } from "./levConvexSetup.sol";

import { UnitTestVault } from "../common/UnitTestVault.sol";

import "hardhat/console.sol";

contract stETHUnit is levConvexSetup, UnitTestVault {
	function getAmnt() public view override(levConvexSetup, SCYStratUtils) returns (uint256) {
		return levConvexSetup.getAmnt();
	}

	function deposit(address user, uint256 amnt) public override(levConvexSetup, SCYStratUtils) {
		levConvexSetup.deposit(user, amnt);
	}

	function testDepositDev() public {
		uint256 amnt = 200000e6;
		deposit(user1, amnt);
		console.log("loanHelath", strategy.loanHealth());
		withdrawEpoch(user1, 1e18);
		uint256 loss = amnt - underlying.balanceOf(user1);
		console.log("year loss", (12 * (10000 * loss)) / amnt);
		console.log("maxTvl", strategy.getMaxTvl());
	}
}
