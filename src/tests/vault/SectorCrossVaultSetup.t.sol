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
import { MockSocketRegistry } from "../mocks/MockSocketRegistry.sol";

import { MiddlewareRequest, BridgeRequest, UserRequest } from "../../common/XChainIntegrator.sol";
import "../../interfaces/MsgStructs.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorCrossVaultTestSetup is SectorTest {
	uint16 chainId;

	uint16 anotherChainId = 1;
	uint16 postmanId = 1;

	WETH underlying;

	SectorCrossVault xVault;
	SectorVault[] vaults;

	LayerZeroPostman postmanLz;
	MultichainPostman postmanMc;
	MockSocketRegistry socketRegistry;

	// address socketRegistry = 0x2b42AFFD4b7C14d9B7C2579229495c052672Ccd3;

	function depositXVault(address acc, uint256 amount) public {
		depositVault(acc, amount, address(xVault));
	}

	function depositVault(
		address acc,
		uint256 amount,
		address vault
	) public {
		SectorBase v = SectorBase(vault);

		vm.deal(acc, amount);

		vm.startPrank(acc);

		// Get some ERC20 for user
		underlying.deposit{ value: amount }();
		underlying.approve(vault, amount);

		// Deposit into Vault
		v.deposit(amount, acc);

		vm.stopPrank();
	}

	function xvaultDepositIntoVaults(
		Request[] memory requests,
		uint256 totalAmount,
		uint256 msgsSent,
		uint256 bridgeEvents,
		bool assertOn
	) public {
		uint256 xVaultFloatAmountBefore = xVault.floatAmnt();

		vm.recordLogs();
		// Deposit into a vault
		vm.prank(manager);
		xVault.depositIntoXVaults(requests);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		if (!assertOn) return;

		// Accounting tests
		assertEq(xVault.totalChildHoldings(), totalAmount, "XVault accounting is correct");
		assertEq(
			xVault.floatAmnt(),
			xVaultFloatAmountBefore - totalAmount,
			"Float amount was reduced by expected"
		);

		// No way of checking if funds arrived on destination chain because has to
		assertGe(
			entries.length,
			requests.length,
			"Has to be emitted at least the number of requests events"
		);

		assertEventCount(entries, "BridgeAsset(uint16,uint16,uint256)", bridgeEvents);
		assertEventCount(entries, "MessageSent(uint256,address,uint16,uint8,address)", msgsSent);
	}

	function xvaultWithdrawFromVaults(
		Request[] memory requests,
		uint256 msgSent,
		uint256 withdrawEvent,
		bool assertOn
	) public {
		uint256[] memory shares = new uint256[](requests.length);
		for (uint256 i = 0; i < requests.length; i++) {
			SectorVault vault = SectorVault(requests[i].vaultAddr);
			shares[i] = vault.balanceOf(address(xVault));
		}

		vm.recordLogs();
		vm.prank(manager);
		xVault.withdrawFromXVaults(requests);

		if (!assertOn) return;

		uint256 requestTimestamp = block.timestamp;

		// Move forward in time and space
		vm.roll(block.number + 100);
		vm.warp(block.timestamp + 100);

		for (uint256 i = 0; i < requests.length; i++) {
			SectorVault vault = SectorVault(requests[i].vaultAddr);
			// uint256 share = shares[i];
			uint256 value = (shares[i] * requests[i].amount) / 1e18;

			(uint16 vaultChainId, , ) = xVault.addrBook(address(vault));
			// On same chain as xVault
			if (vaultChainId == chainId) {
				assertEq(vault.pendingWithdraw(), value, "Pending value must be equal to expected");

				(uint256 ts, uint256 sh, uint256 val) = vault.withdrawLedger(address(xVault));

				assertEq(ts, requestTimestamp, "Withdraw timestamp must be equal to expected");
				assertEq(sh, shares[i], "Shares must be equal to expected");
				assertEq(val, value, "Value assets must be equal to expected");
			}
		}

		Vm.Log[] memory entries = vm.getRecordedLogs();

		assertEventCount(entries, "RequestWithdraw(address,address,uint256)", withdrawEvent);
		assertEventCount(entries, "MessageSent(uint256,address,uint16,uint8,address)", msgSent);
	}

	function xvaultHarvestVault(
		uint256 lDeposit,
		uint256 cDeposit,
		uint256 pAnswers,
		uint256 rAnswers,
		uint256 mSent,
		bool assertOn
	) public {
		vm.recordLogs();
		vm.prank(manager);
		xVault.harvestVaults();

		(
			uint256 localDeposit,
			uint256 crossDeposit,
			uint256 pendingAnswers,
			uint256 receivedAnswers
		) = xVault.harvestLedger();

		if (!assertOn) return;

		assertEq(localDeposit, lDeposit, "Local depoist must be equal to total deposited");
		assertEq(crossDeposit, cDeposit, "Cross deposit value must be expected");
		assertEq(
			pendingAnswers,
			pAnswers,
			"Pending answers must be equal to number of cross vaults"
		);
		assertEq(receivedAnswers, rAnswers, "Received answers must be expected");

		Vm.Log[] memory entries = vm.getRecordedLogs();

		assertEventCount(entries, "MessageSent(uint256,address,uint16,uint8,address)", mSent);
	}

	function xvaultFinalizeHarvest(address[] memory _vaults, uint256[] memory amounts) public {
		uint256 totalAmount = 0;
		for (uint256 i; i < vaults.length; i++) {
			totalAmount += amounts[i];
			if (getVaultChainId(_vaults[i]) == chainId) continue;
			fakeIncomingXDeposit(_vaults[i], amounts[i]);
		}

		// Go back to harvest test
		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(0, 0, 0, 0, 0, false);

		for (uint256 i; i < vaults.length; i++) {
			if (getVaultChainId(_vaults[i]) == chainId) continue;
			fakeAnswerXHarvest(
				_vaults[i],
				SectorVault(vaults[i]).underlyingBalance(address(xVault))
			);
		}

		vm.recordLogs();

		vm.prank(manager);
		xVault.finalizeHarvest(totalAmount, 0);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		// Calculate somehow expectedValue and maxDelta
		assertEq(xVault.totalChildHoldings(), totalAmount, "Harvest was updated value.");
		(uint256 lDeposit, uint256 cDeposit, uint256 pAnswers, uint256 rAnswers) = xVault
			.harvestLedger();
		assertEq(lDeposit, 0, "No more info on harvest Ledger");
		assertEq(cDeposit, 0, "No more info on harvest Ledger");
		assertEq(pAnswers, 0, "No more info on harvest Ledger");
		assertEq(rAnswers, 0, "No more info on harvest Ledger");

		// Harvest(treasury, profit, _performanceFee, _managementFee, feeShares, tvl)
		assertEventCount(entries, "Harvest(address,uint256,uint256,uint256,uint256,uint256)", 1);
	}

	/*//////////////////////////////////////////////////////
						ASSERT HELPERS
	//////////////////////////////////////////////////////*/

	function assertEventCount(
		Vm.Log[] memory entries,
		string memory eventEncoder,
		uint256 count
	) public {
		uint256 foundEvents = 0;
		for (uint256 i = 0; i < entries.length; i++) {
			if (entries[i].topics[0] == keccak256(bytes(eventEncoder))) foundEvents++;
		}
		assertEq(foundEvents, count, string.concat("Events don't match for ", eventEncoder));
	}

	/*//////////////////////////////////////////////////////
						FAKE X CALLS
	//////////////////////////////////////////////////////*/

	function fakeAnswerXHarvest(address vaultAddr, uint256 amount) public {
		vm.startPrank(getPostmanAddr(vaultAddr));
		xVault.receiveMessage(
			Message(amount, vaultAddr, address(0), anotherChainId),
			messageType.HARVEST
		);
		vm.stopPrank();
	}

	function fakeIncomingXDeposit(address vaultAddr, uint256 amount) public {
		SectorVault vault = SectorVault(vaultAddr);

		vm.startPrank(getPostmanAddr(vaultAddr));
		vault.receiveMessage(
			Message(amount, address(xVault), address(0), chainId),
			messageType.DEPOSIT
		);
		vm.stopPrank();

		// Fake that funds arrive after a bridge
		vm.deal(address(vault), amount);
		vm.startPrank(address(vault));
		// Get some ERC20 for vault
		underlying.deposit{ value: amount }();
		vm.stopPrank();

		// Manager process incoming funds
		vm.startPrank(manager);
		vault.processIncomingXFunds();
		vm.stopPrank();
	}

	/*//////////////////////////////////////////////////////
						UTILITIES
	//////////////////////////////////////////////////////*/

	function getPostmanAddr(address vaultAddr) public view returns (address) {
		(uint16 vChainId, uint16 id, ) = xVault.addrBook(vaultAddr);

		return xVault.postmanAddr(id, vChainId);
	}

	function getVaultChainId(address vaultAddr) public view returns (uint16) {
		(uint16 vChainId, , ) = xVault.addrBook(vaultAddr);

		return vChainId;
	}

	function getBasicRequest(
		address vault,
		uint256 toChainId,
		uint256 amount
	) public view returns (Request memory) {
		return
			Request(
				vault,
				amount,
				0,
				address(socketRegistry),
				address(socketRegistry),
				getUserRequest(vault, toChainId, amount, address(underlying))
			);
	}

	function getUserRequest(
		address receiverAddress,
		uint256 toChainId,
		uint256 amount,
		address inputToken
	) public pure returns (bytes memory) {
		BridgeRequest memory br = BridgeRequest(1, 0, inputToken, bytes(""));
		MiddlewareRequest memory mr = MiddlewareRequest(0, 0, inputToken, bytes(""));
		UserRequest memory ur = UserRequest(receiverAddress, toChainId, amount, mr, br);
		return
			abi.encodeWithSignature(
				"outboundTransferTo((address,uint256,uint256,(uint256,uint256,address,bytes),(uint256,uint256,address,bytes)))",
				ur
			);
	}
}
