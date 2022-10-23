// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { SCYVault } from "../mocks/MockScyVault.sol";
import { SCYVaultSetup } from "./SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import { SectorBase, SectorVault, BatchedWithdraw, RedeemParams, DepositParams, ISCYStrategy, AuthConfig, FeeConfig } from "../../vaults/SectorVault.sol";
import { MockERC20, IERC20 } from "../mocks/MockERC20.sol";
import { Endpoint } from "../mocks/MockEndpoint.sol";
import { SectorXVault, Request } from "../../vaults/SectorXVault.sol";
import { LayerZeroPostman, chainPair } from "../../postOffice/LayerZeroPostman.sol";
import { MultichainPostman } from "../../postOffice/MultichainPostman.sol";
import { SectorXVaultTestSetup, MockSocketRegistry } from "./SectorXVaultSetup.t.sol";
import { SectorXVault } from "../../vaults/SectorXVault.sol";

import "../../interfaces/MsgStructs.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorXVaultTest is SectorXVaultTestSetup, SCYVaultSetup {
	uint256 mainnetFork;
	uint256 avaxFork;
	string FUJI_RPC_URL = vm.envString("FUJI_RPC_URL");
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");

	// string MAINNET_RPC_URL = vm.envString("INFURA_COMPLETE_RPC");

	// uint16 anotherChainId = 1;
	// uint16 postmanId = 1;

	// uint16 chainId;

	// WETH underlying;

	// SectorXVault xVault;
	// SectorVault[] vaults;

	// LayerZeroPostman postmanLz;
	// MultichainPostman postmanMc;

	function setUp() public {
		address avaxLzAddr = 0x3c2269811836af69497E5F486A85D7316753cf62;
		// address ethLzAddr = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;

		// Lock on a block number to be cached (goes faster)
		avaxFork = vm.createSelectFork(AVAX_RPC_URL, 21148939);
		chainId = uint16(block.chainid);

		underlying = new WETH();

		uint16[9] memory srcId = [250, 43114, 1284, 5, 43113, 4002, 42161, 10, 1];
		uint16[9] memory dstId = [122, 106, 126, 10121, 10106, 10112, 110, 111, 101];
		chainPair[] memory inptChainPair = new chainPair[](9);
		for (uint256 i = 0; i < srcId.length; i++) inptChainPair[i] = chainPair(srcId[i], dstId[i]);

		// Must be address of layerZero service provider
		postmanLz = new LayerZeroPostman(avaxLzAddr, inptChainPair);

		xVault = new SectorXVault(
			underlying,
			"SECT_X_VAULT",
			"SECT_X_VAULT",
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		// // Config xVault to use postmen
		xVault.managePostman(postmanId, chainId, address(postmanLz));
		xVault.managePostman(postmanId, anotherChainId, address(postmanLz));

		uint256 childVaultsNumber = 10;
		// Deploy a bunch of child vaults
		for (uint256 i = 0; i < childVaultsNumber; i++) {
			vaults.push(
				new SectorVault(
					underlying,
					"SECT_VAULT",
					"SECT_VAULT",
					AuthConfig(owner, guardian, manager),
					FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
				)
			);
			// Pretend that vaults are outside xVault chain
			xVault.addVault(address(vaults[i]), anotherChainId, 1, true);

			socketRegistry = new MockSocketRegistry();

			// Prepare addr book on vaults
			vaults[i].managePostman(postmanId, chainId, address(postmanLz));
			vaults[i].managePostman(postmanId, anotherChainId, address(postmanLz));
			vaults[i].addVault(address(xVault), chainId, 1, true);

			// Add min liquidity
			depositVault(manager, mLp, address(vaults[i]));
		}

		// Must be address of multichain service provider
		// This is breaking because in the constructor calls a function on proxy (executor)
		// postmanMc = new MultichainPostman(address(xVault));

		address[6] memory gaveMoneyAccs = [
			user1,
			user2,
			user3,
			manager,
			guardian,
			address(postmanLz)
		];
		for (uint256 i = 0; i < gaveMoneyAccs.length; i++)
			vm.deal(gaveMoneyAccs[i], 1000000000 ether);

		// Add min liquidity to xVault
		depositXVault(manager, mLp);
	}

	function testOneDepositIntoXVaults() public {
		// Request(addr, amount);
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, true);
	}

	function testMultipleDepositIntoVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount * vaults.length);

		Request[] memory requests = new Request[](vaults.length);
		for (uint256 i; i < vaults.length; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amount);
		}

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(
			requests,
			amount * vaults.length,
			vaults.length,
			vaults.length,
			true
		);
	}

	// 	// Assert from deposit errors
	// 	// Not in addr book

	function testOneWithdrawFromVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, false);

		// uint256 shares = childVault.balanceOf(address(xVault));
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), 1e18);

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 1, 0, true);
	}

	function testMultipleWithdrawFromVaults() public {
		uint256[3] memory amounts = [uint256(1 ether), 918 gwei, 13231 wei];
		// uint256 total = amount1 + amount2 + amount3;
		address[3] memory users = [user1, user2, user3];

		for (uint256 i; i < 3; i++) depositXVault(users[i], amounts[i]);

		uint256 total = 0;
		Request[] memory requests = new Request[](3);
		for (uint256 i; i < 3; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amounts[i]);
			total += amounts[i];
		}

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, total, 0, 0, false);

		for (uint256 i; i < 3; i++)
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), 1e18);

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 3, 0, true);
	}

	function testChainPartialWithdrawFromVaults() public {
		uint256[3] memory amounts = [uint256(1 ether), 918 gwei, 13231 wei];
		// uint256 total = amount1 + amount2 + amount3;
		address[3] memory users = [user1, user2, user3];

		for (uint256 i; i < 3; i++) depositXVault(users[i], amounts[i]);

		uint256 total = 0;
		Request[] memory requests = new Request[](3);
		for (uint256 i; i < 3; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amounts[i]);
			total += amounts[i];
		}

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, total, 0, 0, false);

		uint256[3] memory sharesBefore;
		for (uint256 i; i < 3; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), 1e9);
			sharesBefore[i] = vaults[i].balanceOf(address(xVault));
		}

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 3, 0, true);

		// Check if half of shares were withdraw
		for (uint256 i; i < 3; i++) {
			assertEq(vaults[i].balanceOf(address(xVault)), sharesBefore[i] / 2);
		}
	}

	// 	// Assert errors

	function testOneChainHarvestVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		// getRequests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(
			0,
			vaults[0].balanceOf(address(xVault)),
			vaults.length,
			0,
			vaults.length,
			true
		);
	}

	function testMultipleHarvestVaults() public {
		uint256[3] memory amounts = [uint256(1 ether), 918 gwei, 13231 wei];
		address[3] memory users = [user1, user2, user3];

		for (uint256 i; i < 3; i++) depositXVault(users[i], amounts[i]);

		uint256 total = 0;
		Request[] memory requests = new Request[](3);
		for (uint256 i; i < 3; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amounts[i]);
			total += amounts[i];
		}

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, total, 0, 0, false);

		uint256 totalShares = 0;
		for (uint256 i; i < 3; i++) totalShares += vaults[i].balanceOf(address(xVault));

		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(0, totalShares, vaults.length, 0, vaults.length, true);
	}

	// 	// More variations on that (no messages for example)

	function testOneFinalizeHarvest() public {
		uint256[] memory amount = new uint256[](vaults.length);
		amount[0] = 1 ether;
		for (uint256 i = 1; i < vaults.length; i++) amount[i] = 0;

		depositXVault(user1, amount[0]);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount[0]);

		// getRequests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount[0], 0, 0, false);

		xvaultFinalizeHarvest(amount);
	}

	function testMultipleFinalizeHarvest() public {
		uint256[] memory amount = new uint256[](vaults.length);

		amount[0] = 1 ether;
		uint256 total = amount[0];
		for (uint256 i = 1; i < vaults.length; i++) {
			amount[i] = i * 1209371 gwei;
			total += amount[i];
		}
		depositXVault(user1, total);

		Request[] memory requests = new Request[](vaults.length);
		for (uint256 i; i < vaults.length; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amount[i]);
		}

		// getRequests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, total, 0, 0, false);

		xvaultFinalizeHarvest(amount);
	}

	// 	// // Assert errors

	function testOneEmergencyWithdrawVaults() public {
		// Request(addr, amount);
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		vm.prank(user1);
		xVault.emergencyWithdraw();

		assertEq(xVault.balanceOf(user1), 0);
	}

	function testMultipleEmergencyWithdrawVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount * vaults.length);

		Request[] memory requests = new Request[](vaults.length);
		for (uint256 i; i < vaults.length; i++) {
			requests[i] = getBasicRequest(address(vaults[i]), uint256(anotherChainId), amount);
		}

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(
			requests,
			amount * vaults.length,
			vaults.length,
			vaults.length,
			true
		);

		vm.prank(user1);
		xVault.emergencyWithdraw();

		assertEq(xVault.balanceOf(user1), 0);
	}

	// Passive calls (receive message)

	function testReceiveWithdraw() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, false);

		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), 1e18);
		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 0, 0, false);

		uint256 beforeFinalize = xVault.totalChildHoldings();
		assertEq(beforeFinalize, amount);

		// Fake receiving funds from another chain
		vm.deal(address(xVault), amount);
		vm.prank(address(xVault));
		underlying.deposit{ value: amount }();

		// Fake receiving message from another chain
		vm.prank(address(postmanLz));
		xVault.receiveMessage(
			Message(amount, address(vaults[0]), address(0), anotherChainId),
			MessageType.WITHDRAW
		);

		vm.prank(manager);
		vm.expectEmit(false, false, false, false);
		emit RegisterIncomingFunds(amount);
		xVault.processIncomingXFunds();

		uint256 afterFinalize = xVault.totalChildHoldings();
		assertEq(afterFinalize, beforeFinalize - amount);
	}

	// Vault management

	function testAddVault() public {
		address newVault = address(0xffffffffffff);
		vm.expectEmit(true, false, false, true);
		emit AddedVault(newVault, chainId);

		vm.prank(owner);
		xVault.addVault(newVault, chainId, 1, true);

		(uint16 cId, uint16 pId, bool isAllowed) = xVault.addrBook(newVault);
		assertEq(isAllowed, true);
		assertEq(pId, 1);
		assertEq(cId, chainId);
	}

	function testRemoveVault() public {
		address removedVault = address(vaults[0]);
		vm.expectEmit(true, false, false, true);
		emit ChangedVaultStatus(removedVault, false);

		vm.prank(owner);
		xVault.removeVault(removedVault);

		(, , bool isAllowed) = xVault.addrBook(removedVault);
		assertEq(isAllowed, false);

		// Also, needs to test if vault was removed from vaultList
		// lDeposit, cDeposit, pAnswers, rAnswers, mSent, assertOn
		xvaultHarvestVault(0, 0, vaults.length - 1, 0, vaults.length - 1, true);
	}

	function testCannotInteractAfterRemove() public {
		address removedVault = address(vaults[0]);
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		vm.prank(owner);
		xVault.removeVault(removedVault);

		Request[] memory requests = new Request[](1);
		requests[0] = getBasicRequest(address(vaults[0]), uint256(anotherChainId), amount);

		vm.expectRevert(abi.encodeWithSelector(VaultNotAllowed.selector, removedVault));
		vm.prank(manager);
		xVault.depositIntoXVaults(requests);
	}

	function testChangeVaultStatus() public {
		address testVault = address(vaults[1]);
		vm.expectEmit(true, false, false, true);
		emit ChangedVaultStatus(testVault, false);

		vm.prank(owner);
		xVault.changeVaultStatus(testVault, false);

		(, , bool isFalse) = xVault.addrBook(testVault);
		assertEq(isFalse, false);

		vm.prank(owner);
		xVault.changeVaultStatus(testVault, true);

		(, , bool isTrue) = xVault.addrBook(testVault);
		assertEq(isTrue, true);
	}

	function testUpdateVaultPostman() public {
		address testVault = address(vaults[1]);
		uint16 newPostmanId = 2;
		vm.expectEmit(true, false, false, true);
		emit UpdatedVaultPostman(testVault, newPostmanId);

		vm.prank(owner);
		xVault.updateVaultPostman(testVault, newPostmanId);

		(, uint16 postId, ) = xVault.addrBook(testVault);
		assertEq(postId, newPostmanId);
	}

	function testManagePostman() public {
		uint16 newPostmanId = 2;
		uint16 newChainId = 1337;
		address newPostman = address(0xffffffffffff);

		vm.expectEmit(true, false, false, true);
		emit PostmanUpdated(newPostmanId, newChainId, newPostman);

		vm.prank(owner);
		xVault.managePostman(newPostmanId, newChainId, newPostman);

		address checkPostman = xVault.postmanAddr(newPostmanId, newChainId);

		assertEq(checkPostman, newPostman);
	}

	// Copied from SectorXVault to test
	/*/////////////////////////////////////////////////////
							Events
	/////////////////////////////////////////////////////*/

	event AddedVault(address indexed vault, uint16 chainId);
	event ChangedVaultStatus(address indexed vault, bool status);
	event UpdatedVaultPostman(address indexed vault, uint16 postmanId);
	event PostmanUpdated(uint16 indexed postmanId, uint16 chanId, address postman);
	event BridgeAsset(uint16 _fromChainId, uint16 _toChainId, uint256 amount);
	event RegisterIncomingFunds(uint256 total);

	/*/////////////////////////////////////////////////////
							Errors
	/////////////////////////////////////////////////////*/

	error SenderNotAllowed(address sender);
	error WrongPostman(address postman);
	error VaultNotAllowed(address vault);
	error VaultMissing(address vault);
	error VaultAlreadyAdded();
	error BridgeError();
	error SameChainOperation();
	error MissingIncomingXFunds();
}
