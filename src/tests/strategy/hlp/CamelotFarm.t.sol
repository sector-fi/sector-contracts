// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IUniswapV2Pair } from "interfaces/uniswap/IUniswapV2Pair.sol";
import { HarvestSwapParams } from "strategies/mixins/IFarmable.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeETH } from "libraries/SafeETH.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { HLPSetup, SCYVault, HLPCore } from "./HLPSetup.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";
import { UnitTestStrategy } from "../common/UnitTestStrategy.sol";
import { SectorErrors } from "interfaces/SectorErrors.sol";
import { AggregatorVault } from "vaults/sectorVaults/AggregatorVault.sol";
import { CamelotFarm, IXGrailToken, INFTPool } from "strategies/modules/camelot/CamelotFarm.sol";

import "hardhat/console.sol";

contract CamelotFarmTest is HLPSetup {
	function testCamelotFarm() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();

		CamelotFarm cFarm = CamelotFarm(address(strategy));

		INFTPool farm = INFTPool(cFarm.farm());
		uint256 positionId = cFarm.positionId();
		IXGrailToken xGrailToken = cFarm.xGrailToken();
		address yieldBooster = cFarm.yieldBooster();
		uint256 xGrailAllocation = xGrailToken.usageAllocations(address(strategy), yieldBooster);
		assertGt(xGrailAllocation, 0, "xGrailAllocation should be greater than 0");

		(
			uint256 amount,
			uint256 amountWithMultiplier,
			uint256 startLockTime,
			uint256 lockDuration,
			uint256 lockMultiplier,
			uint256 rewardDebt,
			uint256 boostPoints,
			uint256 totalMultiplier
		) = farm.getStakingPosition(positionId);

		assertGt(amount, 0, "amount should be gt 0");
		assertGt(boostPoints, 0, "boostPoints should be greater than 0");
		uint256 xGrailBal = xGrailToken.balanceOf(address(strategy));
		assertEq(xGrailBal, 0, "xGrailBal should be 0");

		skip(1);
		vault.closePosition(0, 0);
		xGrailAllocation = xGrailToken.usageAllocations(address(strategy), yieldBooster);
		assertEq(xGrailAllocation, 0, "xGrailAllocation should be 0");

		xGrailBal = xGrailToken.balanceOf(address(strategy));
		assertGt(xGrailBal, 0, "xGrailBal should be greater than 0");
	}
}
