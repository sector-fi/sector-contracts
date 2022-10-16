// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorBase, SectorVault, BatchedWithdraw, RedeemParams, DepositParams, ISCYStrategy, AuthConfig, FeeConfig } from "../../vaults/SectorVault.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { Endpoint } from "../mocks/MockEndpoint.sol";
import { SectorCrossVault, Request } from "../../vaults/SectorCrossVault.sol";
import { LayerZeroPostman, chainPair } from "../../postOffice/LayerZeroPostman.sol";
import { MultichainPostman } from "../../postOffice/MultichainPostman.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorCrossVaultTestSetup is SectorTest {
	// ISCYStrategy strategy1;
	// ISCYStrategy strategy2;
	// ISCYStrategy strategy3;

	uint16 chainId;

	WETH underlying;

	SectorCrossVault xVault;
	SectorVault childVault;
	SectorVault nephewVault;

	LayerZeroPostman postmanLz;
	MultichainPostman postmanMc;

	function depositXVault(address acc, uint256 amount) public {
		vm.startPrank(acc);

		// Get some ERC20 for user
		underlying.deposit{ value: amount }();
		underlying.approve(address(xVault), amount);

		// Deposit into XVault
		xVault.deposit(amount, address(user1));

		vm.stopPrank();
	}

	function xvaultDepositIntoVaults(Request[] memory requests, uint256 amount, uint256 msgsSent, uint256 bridgeEvents) public {
		vm.recordLogs();
		// Deposit into a vault
		vm.prank(manager);
		xVault.depositIntoVaults(requests);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		assertEq(xVault.totalChildHoldings(), amount, "XVault accounting is correct");
		// assertEq(childVault.underlyingBalance(address(xVault)), amount);
		assertGe(entries.length, requests.length, "Has to be emitted at least the number of requests events");

		uint256 foundBridgeEvents = 0;
		uint256 foundMessageSent = 0;
		for (uint256 i = 0; i < entries.length; i++) {
			if (entries[i].topics[0] == keccak256("BridgeAsset(uint16,uint16,uint256)")) {
				foundBridgeEvents++;
			} else if (
				entries[i].topics[0] ==
				keccak256("MessageSent(uint256,address,uint16,uint8,address)")
			) {
				foundMessageSent++;
			}
		}
		// Only one bridge events has to emitted
		assertEq(foundBridgeEvents, bridgeEvents, "Expected bridge events not found");
		// Only one message sent
		assertEq(foundMessageSent, msgsSent, "Expected message sent not found");

	}
}
