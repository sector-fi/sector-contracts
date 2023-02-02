// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ISCYStrategy } from "interfaces/ERC5115/ISCYStrategy.sol";
import { SectorErrors } from "interfaces/SectorErrors.sol";
import { SCYStratUtils } from "./SCYStratUtils.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";

import "hardhat/console.sol";

abstract contract StratAuthTest is SCYStratUtils {
	address rando = address(99);

	function testAuth() public {
		vm.startPrank(rando);

		vm.expectRevert(SectorErrors.OnlyVault.selector);
		ISCYStrategy(address(strat)).deposit(1);

		vm.expectRevert(SectorErrors.OnlyVault.selector);
		ISCYStrategy(address(strat)).redeem(rando, 1);

		vm.expectRevert(SectorErrors.OnlyVault.selector);
		ISCYStrategy(address(strat)).closePosition(0);

		vm.expectRevert(SectorErrors.OnlyVault.selector);
		ISCYStrategy(address(strat)).harvest(
			new HarvestSwapParams[](0),
			new HarvestSwapParams[](0)
		);

		vm.stopPrank();
	}
}
