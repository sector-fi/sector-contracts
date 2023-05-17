// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IStrategy } from "interfaces/IStrategy.sol";
import { HLPSetup, SCYVault, HLPCore } from "./HLPSetup.sol";
import { CamelotFarm, IXGrailToken, INFTPool } from "strategies/modules/camelot/CamelotFarm.sol";
import { CamelotSectGrailFarm, ISectGrail } from "strategies/modules/camelot/CamelotSectGrailFarm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { sectGrail as SectGrail } from "strategies/modules/camelot/sectGrail.sol";

import "hardhat/console.sol";

contract CamelotFarmTest is HLPSetup {
	function getStrategy() public pure override returns (string memory) {
		return "HLP_USDC-ETH_Camelot_arbitrum";
	}

	CamelotSectGrailFarm cFarm;
	INFTPool farm;
	ISectGrail sectGrail;
	IXGrailToken xGrailToken;
	IERC20 grailToken;

	function setupHook() public override {
		cFarm = CamelotSectGrailFarm(address(strategy));
		farm = INFTPool(cFarm.farm());
		sectGrail = cFarm.sectGrail();
		xGrailToken = sectGrail.xGrailToken();
		grailToken = IERC20(sectGrail.grailToken());

		// whitelist farm and yieldBooster
		sectGrail.updateWhitelist(address(farm), true);
		sectGrail.updateWhitelist(farm.yieldBooster(), true);
	}

	function testCamelotFarm() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();

		uint256 positionId = cFarm.positionId();

		address yieldBooster = farm.yieldBooster();
		uint256 xGrailAllocation = xGrailToken.usageAllocations(address(sectGrail), yieldBooster);
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
		uint256 xGrailBal = xGrailToken.balanceOf(address(sectGrail));
		assertEq(xGrailBal, 0, "xGrailBal should be 0");

		skip(1);
		vault.closePosition(0, 0);
		xGrailAllocation = xGrailToken.usageAllocations(address(sectGrail), yieldBooster);
		assertEq(xGrailAllocation, 0, "xGrailAllocation should be 0");

		xGrailBal = xGrailToken.balanceOf(address(sectGrail));
		assertGt(xGrailBal, 0, "xGrailBal should be greater than 0");
	}

	function testCamelotDealocate() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();
		uint256 allocated = sectGrail.getAllocations(address(strategy));
		cFarm.deallocateSectGrail(allocated);
		allocated = sectGrail.getAllocations(address(strategy));
		assertEq(allocated, 0, "allocated should be 0");
	}

	function testCamelotTransferSectGrail() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();
		uint256 allocated = sectGrail.getAllocations(address(strategy));

		vm.expectRevert(SectGrail.CannotTransferAllocatedTokens.selector);
		cFarm.transferSectGrail(self, allocated);

		cFarm.deallocateSectGrail(allocated);
		uint256 balance = IERC20(address(sectGrail)).balanceOf(address(strategy));
		cFarm.transferSectGrail(self, balance);
		allocated = sectGrail.getAllocations(address(strategy));
		assertEq(allocated, 0, "allocated should be 0");
	}

	function testNotPositionOwner() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		harvest();

		uint256 positionId = cFarm.positionId();
		uint256 lpAmount = sectGrail.getFarmLp(farm, positionId);
		address lpToken = address(cFarm.pair());

		vm.expectRevert(SectGrail.NotPositionOwner.selector);
		sectGrail.withdrawFromFarm(farm, positionId, lpAmount);

		deal(lpToken, self, lpAmount);
		IERC20(lpToken).approve(address(sectGrail), lpAmount);
		vm.expectRevert(SectGrail.NotPositionOwner.selector);
		sectGrail.depositIntoFarm(farm, positionId, lpAmount);

		vm.expectRevert(SectGrail.NotPositionOwner.selector);
		sectGrail.harvestFarm(farm, positionId);
	}

	function testDeposit() public {
		if (!compare(contractType, "CamelotAave")) return;
		uint256 amnt = getAmnt();
		deposit(self, amnt);
		uint256 cFarmPositionId = cFarm.positionId();
		uint256 lpAmount = sectGrail.getFarmLp(farm, cFarmPositionId);
		address lpToken = address(cFarm.pair());

		deal(lpToken, self, lpAmount);
		IERC20(lpToken).approve(address(sectGrail), lpAmount);
		uint256 selfPositionId = sectGrail.depositIntoFarm(farm, 0, lpAmount);

		skip(15 days);
		harvest();

		sectGrail.harvestFarm(farm, selfPositionId);

		uint256 allocation1 = sectGrail.getAllocations(address(strategy));
		uint256 allocation2 = sectGrail.getAllocations(address(self));
		assertApproxEqRel(
			allocation1,
			allocation2,
			.0001e18,
			"allocation1 should be equal to allocation2"
		);

		sectGrail.deallocateFromPosition(farm, selfPositionId, allocation2);

		uint256 afterDeallocate = sectGrail.getAllocations(self);
		assertEq(afterDeallocate, 0, "afterDeallocate should be 0");

		vm.expectRevert(SectGrail.NotPositionOwner.selector);
		sectGrail.deallocateFromPosition(farm, cFarmPositionId, allocation1);
	}
}
