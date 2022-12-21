// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { stETHSetup, SCYStratUtils } from "./stETHSetup.sol";

import { UnitTestVault } from "../common/UnitTestVault.sol";

import "hardhat/console.sol";

// contract stETHUnit is stETHSetup, UnitTestVault {
// 	function getAmnt() public view override(stETHSetup, SCYStratUtils) returns (uint256) {
// 		return stETHSetup.getAmnt();
// 	}

// 	function deposit(address user, uint256 amnt) public override(stETHSetup, SCYStratUtils) {
// 		stETHSetup.deposit(user, amnt);
// 	}
// }
