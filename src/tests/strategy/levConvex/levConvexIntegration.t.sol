// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IntegrationTestWEpoch, SCYStratUtils } from "../common/IntegrationTestWEpoch.sol";
import { FlashSwapTest } from "../common/FlashSwapTest.sol";
import { levConvexSetup } from "./levConvexSetup.sol";

contract levConvexSetupIntegration is IntegrationTestWEpoch, levConvexSetup {
	function getAmnt() public view override(levConvexSetup, SCYStratUtils) returns (uint256) {
		return levConvexSetup.getAmnt();
	}

	function deposit(address user, uint256 amnt) public override(levConvexSetup, SCYStratUtils) {
		levConvexSetup.deposit(user, amnt);
	}
}
