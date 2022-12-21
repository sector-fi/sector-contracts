// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IntegrationTestWEpoch, SCYStratUtils } from "../common/IntegrationTestWEpoch.sol";
import { FlashSwapTest } from "../common/FlashSwapTest.sol";
import { stETHSetup } from "./stETHSetup.sol";

// contract stEthIntegration is IntegrationTestWEpoch, stETHSetup {
// 	function getAmnt() public view override(stETHSetup, SCYStratUtils) returns (uint256) {
// 		return stETHSetup.getAmnt();
// 	}

// 	function deposit(address user, uint256 amnt) public override(stETHSetup, SCYStratUtils) {
// 		stETHSetup.deposit(user, amnt);
// 	}
// }
