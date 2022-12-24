// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorBase, SectorVault, RedeemParams, DepositParams, AuthConfig, FeeConfig } from "vaults/sectorVaults/SectorVault.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { Endpoint } from "../mocks/MockEndpoint.sol";
import { SectorXVault, Request } from "vaults/sectorVaults/SectorXVault.sol";
import { LayerZeroPostman, chainPair } from "../../xChain/LayerZeroPostman.sol";
import { MultichainPostman } from "../../xChain/MultichainPostman.sol";
import { MockSocketRegistry } from "../mocks/MockSocketRegistry.sol";

import { MiddlewareRequest, BridgeRequest, UserRequest } from "../../libraries/XChainLib.sol";
import "../../interfaces/MsgStructs.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorXVaultSetup is SectorTest {
	uint16 chainId;

	uint16 anotherChainId = 1;
	uint16 postmanId = 1;

	WETH underlying;

	SectorXVault xVault;
	SectorVault[] vaults;

	LayerZeroPostman postmanLz;
	MultichainPostman postmanMc;
	MockSocketRegistry socketRegistry;

	// address socketRegistry = 0x2b42AFFD4b7C14d9B7C2579229495c052672Ccd3;

	function depositXVault(address acc, uint256 amount) public {
		depositVault(acc, amount, payable(xVault));
	}

	function depositVault(
		address acc,
		uint256 amount,
		address payable vault
	) public {
		SectorBase v = SectorBase(vault);

		vm.deal(acc, amount + acc.balance);

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
		bool assertOn,
		uint256 messageFee
	) public payable {
		uint256 xVaultFloatAmountBefore = xVault.floatAmnt();

		vm.recordLogs();
		// Deposit into a vault
		vm.prank(manager);
		xVault.depositIntoXVaults{ value: messageFee }(requests);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		for (uint256 i; i < requests.length; i++) {
			SectorVault vault = SectorVault(payable(requests[i].vaultAddr));
			mockReceiveFunds(
				vault,
				address(xVault),
				chainId,
				requests[i].vaultChainId,
				requests[i].amount
			);
		}

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
		bool assertOn,
		uint256 messageFee
	) public {
		uint256[] memory shares = new uint256[](requests.length);
		address xAddr = xVault.getXAddr(address(xVault), chainId);

		for (uint256 i; i < requests.length; i++) {
			SectorVault vault = SectorVault(payable(requests[i].vaultAddr));
			shares[i] = vault.balanceOf(xAddr);
			receiveMessage(
				vault,
				requests[i].vaultChainId,
				Message(requests[i].amount, address(xVault), address(0), chainId),
				MessageType.WITHDRAW
			);
		}

		vm.recordLogs();
		vm.prank(manager);
		xVault.withdrawFromXVaults{ value: messageFee }(requests);

		if (!assertOn) return;

		uint256 requestTimestamp = block.timestamp;

		// Move forward in time and space
		vm.roll(block.number + 100);
		vm.warp(block.timestamp + 100);

		for (uint256 i; i < requests.length; i++) {
			SectorVault vault = SectorVault(payable(requests[i].vaultAddr));

			uint256 vaultShares = shares[i];
			uint256 vaultBalance = vault.convertToAssets(vaultShares);
			uint256 value = (requests[i].amount * vaultBalance) / 1e18;
			uint256 redeemShares = (requests[i].amount * vaultShares) / 1e18;

			uint256 pendingWithdraw = vault.convertToAssets(vault.pendingRedeem());
			assertEq(pendingWithdraw, value, "Pending value must be equal to expected");

			(uint256 ts, uint256 sh, uint256 val) = vault.withdrawLedger(xAddr);

			assertEq(ts, requestTimestamp, "Withdraw timestamp must be equal to expected");
			assertEq(sh, redeemShares, "Shares must be equal to expected");
			assertEq(val, value, "Value assets must be equal to expected");
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

		Request[] memory requests = new Request[](vaults.length);
		for (uint256 i; i < vaults.length; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), 0);
		}

		vm.prank(manager);
		uint256 messageFee = xVault.estimateMessageFee(requests, MessageType.HARVEST);

		vm.prank(manager);
		xVault.harvestVaults{ value: messageFee }();

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

	function xvaultFinalizeHarvest(uint256[] memory amounts) public {
		uint256 totalAmount = 0;
		for (uint256 i; i < vaults.length; i++) {
			totalAmount += amounts[i];
			fakeIncomingXDeposit(payable(vaults[i]), amounts[i]);
		}

		// Go back to harvest test
		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(0, 0, 0, 0, 0, false);

		for (uint256 i; i < vaults.length; i++) {
			fakeAnswerXHarvest(address(vaults[i]), amounts[i]);
		}

		vm.recordLogs();

		vm.prank(manager);
		xVault.finalizeHarvest(totalAmount, 0);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		// Calculate somehow expectedValue and maxDelta
		assertEq(xVault.totalChildHoldings(), totalAmount, "Harvest has updated value.");
		(uint256 lDeposit, uint256 cDeposit, uint256 pAnswers, uint256 rAnswers) = xVault
			.harvestLedger();
		assertEq(lDeposit, 0, "No more info on harvest Ledger");
		assertEq(cDeposit, 0, "No more info on harvest Ledger");
		assertEq(pAnswers, 0, "No more info on harvest Ledger");
		assertEq(rAnswers, 0, "No more info on harvest Ledger");

		// Harvest(treasury, profit, _performanceFee, _managementFee, feeShares, tvl)
		assertEventCount(entries, "Harvest(address,uint256,uint256,uint256,uint256,uint256)", 1);
	}

	function receiveXDepositVault(
		uint256 amount,
		address payable[] memory _vaults,
		bool assertOn
	) public {
		// Request(addr, amount);
		// uint256 amount = 1 ether;

		uint256 amountStep = amount / _vaults.length;

		depositXVault(user1, amount);

		for (uint256 i; i < _vaults.length; i++) {
			SectorVault v = SectorVault(_vaults[i]);

			receiveMessage(
				v,
				anotherChainId,
				Message(amountStep, address(xVault), address(0), chainId),
				MessageType.DEPOSIT
			);

			vm.prank(address(xVault));
			underlying.transfer(address(v), amountStep);
		}

		if (!assertOn) return;

		for (uint256 i; i < _vaults.length; i++) {
			SectorVault v = SectorVault(_vaults[i]);

			(uint256 _value, address _sender, address _client, uint16 _chainId) = v.incomingQueue(
				0
			);

			assertEq(_value, amountStep);
			assertEq(_sender, address(xVault));
			assertEq(_client, address(0));
			assertEq(_chainId, chainId);
			assertEq(v.getIncomingQueueLength(), 1, "Incoming queue length must be equal to one");
		}
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
		for (uint256 i; i < entries.length; i++) {
			if (entries[i].topics[0] == keccak256(bytes(eventEncoder))) foundEvents++;
		}
		assertEq(foundEvents, count, string.concat("Events don't match for ", eventEncoder));
	}

	/*//////////////////////////////////////////////////////
						FAKE X CALLS
	//////////////////////////////////////////////////////*/

	function fakeAnswerXHarvest(address vaultAddr, uint256 amount) public {
		vm.startPrank(getPostmanAddr(vaultAddr, anotherChainId));
		xVault.receiveMessage(
			Message(amount, vaultAddr, address(0), anotherChainId),
			MessageType.HARVEST
		);
		vm.stopPrank();
	}

	function fakeIncomingXDeposit(address payable vaultAddr, uint256 amount) public {
		SectorVault vault = SectorVault(vaultAddr);

		vm.startPrank(getPostmanAddr(vaultAddr, anotherChainId));
		vault.receiveMessage(
			Message(amount, address(xVault), address(0), chainId),
			MessageType.DEPOSIT
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

	function getPostmanAddr(address vaultAddr, uint16 vaultChainId) public returns (address) {
		(uint16 id, ) = xVault.addrBook(xVault.getXAddr(vaultAddr, vaultChainId));

		return xVault.postmanAddr(id, vaultChainId);
	}

	// function getVaultChainId(address vaultAddr) public view returns (uint16) {
	// 	(uint16 vChainId, , ) = xVault.addrBook(vaultAddr);

	// 	return vChainId;
	// }

	function getBasicRequest(
		address vault,
		uint256 toChainId,
		uint256 amount
	) public view returns (Request memory) {
		return
			Request(
				vault,
				uint16(toChainId),
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

	function mockReceiveFunds(
		SectorVault vault,
		address from,
		uint16 fromChain,
		uint16 toChain,
		uint256 amount
	) public {
		receiveMessage(
			vault,
			toChain,
			Message(amount, from, address(0), fromChain),
			MessageType.DEPOSIT
		);

		vm.startPrank(manager);

		deal(address(underlying), manager, amount);
		underlying.transfer(address(vault), amount);

		vault.processIncomingXFunds();

		address xSrcAddr = vault.getXAddr(from, fromChain);
		uint256 _srcVaultUnderlyingBalance = vault.estimateUnderlyingBalance(xSrcAddr);

		assertEq(amount, _srcVaultUnderlyingBalance);

		vm.stopPrank();
	}

	// Mocks a message being received from another chain
	function receiveMessage(
		SectorVault _dstVault,
		uint16 toChain,
		Message memory _msg,
		MessageType _msgType
	) public {
		bytes memory _payload = abi.encode(_msg, address(_dstVault), _msgType);

		address postmanAddr = getPostmanAddr(address(_dstVault), toChain);
		LayerZeroPostman postman = LayerZeroPostman(postmanAddr);
		address lzEndpoint = address(postman.endpoint());

		vm.startPrank(lzEndpoint);

		bytes memory mock = abi.encode(_msg.sender);
		uint16 lzSrcId = postman.chains(_msg.chainId);
		postman.lzReceive(lzSrcId, mock, 1, _payload);

		vm.stopPrank();
	}
}
