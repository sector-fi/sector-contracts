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
import { SectorCrossVaultTestSetup } from "./SectorCrossVaultSetup.t.sol";
import "../../interfaces/MsgStructs.sol";

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorCrossVaultTest is SectorCrossVaultTestSetup, SCYVaultSetup {
	uint256 mainnetFork;
	uint256 avaxFork;
	string FUJI_RPC_URL = vm.envString("FUJI_RPC_URL");
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	string MAINNET_RPC_URL = vm.envString("INFURA_COMPLETE_RPC");

	// uint16 anotherChainId = 1;
	// uint16 postmanId = 1;

	// uint16 chainId;

	// WETH underlying;

	// SectorCrossVault xVault;
	// SectorVault childVault;
	// SectorVault nephewVault;

	// LayerZeroPostman postmanLz;
	// MultichainPostman postmanMc;

	function setUp() public {
		address avaxLzAddr = 0x3c2269811836af69497E5F486A85D7316753cf62;
		// address ethLzAddr = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;

		// Lock on a block number to be cached (goes faster)
		avaxFork = vm.createSelectFork(AVAX_RPC_URL, 21148939);
		chainId = uint16(block.chainid);

		underlying = new WETH();

		xVault = new SectorCrossVault(
			underlying,
			"SECT_X_VAULT",
			"SECT_X_VAULT",
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		childVault = new SectorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		nephewVault = new SectorVault(
			underlying,
			"SECT_OTHER_VAULT",
			"SECT_OTHER_VAULT",
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE)
		);

		// F*** stupid
		chainPair[] memory inptChainPair = new chainPair[](9);
		inptChainPair[0] = chainPair(250, 122);
		inptChainPair[1] = chainPair(43114, 106);
		inptChainPair[2] = chainPair(1284, 126);
		inptChainPair[3] = chainPair(5, 10121);
		inptChainPair[4] = chainPair(43113, 10106);
		inptChainPair[5] = chainPair(4002, 10112);
		inptChainPair[6] = chainPair(42161, 110);
		inptChainPair[7] = chainPair(10, 111);
		inptChainPair[8] = chainPair(1, 101);

		// Must be address of layerZero service provider
		postmanLz = new LayerZeroPostman(avaxLzAddr, inptChainPair);

		// Must be address of multichain service provider
		// This is breaking because in the constructor calls a function on proxy (executor)
		// postmanMc = new MultichainPostman(address(xVault));

		// // Config both vaults to use postmen
		xVault.managePostman(postmanId, chainId, address(postmanLz));
		xVault.managePostman(postmanId, anotherChainId, address(postmanLz));
		// xVault.managePostman(2, chainId, address(postmanMc));
		xVault.addVault(address(childVault), chainId, 1, true);
		// Pretend that is on other chain
		xVault.addVault(address(nephewVault), anotherChainId, 1, true);

		childVault.managePostman(postmanId, chainId, address(postmanLz));
		// childVault.managePostman(2, chainId, address(postmanMc));
		childVault.addVault(address(xVault), chainId, 1, true);
		childVault.addVault(address(nephewVault), anotherChainId, 1, true);

		// Still not sure about this part yet
		nephewVault.managePostman(postmanId, chainId, address(postmanLz));
		// nephewVault.managePostman(2, chainId, address(postmanMc));
		nephewVault.addVault(address(xVault), chainId, 1, true);
		nephewVault.addVault(address(childVault), chainId, 1, true);

		vm.deal(user1, 10 ether);
		vm.deal(user2, 10 ether);
		vm.deal(user3, 10 ether);
		vm.deal(manager, 10 ether);
		vm.deal(guardian, 10 ether);
		// Postman needs native to pay provider.
		vm.deal(address(postmanLz), 10 ether);

		// To prevent rounding attacks (to fix accounting is this case)
		depositXVault(manager, mLp);
	}

	function testOneChainDepositIntoVaults() public {
		// Request(addr, amount);
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, true);
	}

	function testOneCrossDepositIntoVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, true);
	}

	function testMultipleDepositIntoVauls() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount * 2);

		Request[] memory requests = new Request[](2);
		requests[0] = Request(address(childVault), amount);
		requests[1] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount * 2, 1, 1, true);
	}

	function testMultipleUsersDepositIntoVaults() public {
		uint256 amount1 = 1 ether;
		uint256 amount2 = 123424323 wei;
		uint256 amount3 = 3310928371 wei;

		depositXVault(user1, amount1);
		depositXVault(user2, amount2);
		depositXVault(user3, amount3);

		Request[] memory requests = new Request[](3);
		requests[0] = Request(address(childVault), amount1);
		requests[1] = Request(address(nephewVault), amount2);
		requests[2] = Request(address(nephewVault), amount3);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, (amount1 + amount2 + amount3), 2, 2, true);
	}

	// // Assert from deposit errors
	// // Not in addr book

	function testOneChainWithdrawFromVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, false);

		// uint256 shares = childVault.balanceOf(address(xVault));
		requests[0] = Request(address(childVault), 100);

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 0, 1, true);
	}

	function testOneCrossWithdrawFromVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1, false);

		// uint256 shares = nephewVault.balanceOf(address(xVault));
		requests[0] = Request(address(nephewVault), 100);

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 1, 0, true);
	}

	function testMultipleWithdrawFromVaults() public {
		uint256 amount1 = 1 ether;
		uint256 amount2 = 918 gwei;
		uint256 amount3 = 13231 wei;

		depositXVault(user1, amount1);
		depositXVault(user2, amount2);
		depositXVault(user3, amount3);

		Request[] memory requests = new Request[](3);
		requests[0] = Request(address(childVault), amount1);
		requests[1] = Request(address(nephewVault), amount2);
		requests[2] = Request(address(nephewVault), amount3);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, (amount1 + amount2 + amount3), 0, 0, false);

		requests[0] = Request(address(childVault), 100);
		requests[1] = Request(address(nephewVault), 100);
		requests[2] = Request(address(nephewVault), 100);

		// Requests, total amount, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 2, 1, true);
	}

	function testChainPartialWithdrawFromVaults() public {
		uint256 amount1 = 1 ether;

		depositXVault(user1, amount1);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount1);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount1, 0, 0, false);

		uint256 sharesBefore = childVault.balanceOf(address(xVault));
		uint256 sharesWithdraw = (childVault.balanceOf(address(xVault)) * 25) / 100;
		requests[0] = Request(address(childVault), 25);
		// Requests, msgSent events, withdraw events
		xvaultWithdrawFromVaults(requests, 0, 0, false);

		assertEq(childVault.balanceOf(address(xVault)), sharesBefore - sharesWithdraw);
	}

	// Assert errors

	function testOneChainHarvestVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(childVault.balanceOf(address(xVault)), 0, 1, 0, 1, true);
	}

	function testOneCrossHarvestVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(0, nephewVault.balanceOf(address(xVault)), 1, 0, 1, true);
	}

	function testMultipleHarvestVaults() public {
		uint256 amount1 = 1 ether;
		uint256 amount2 = 1987198723 wei;
		uint256 amount3 = 389 gwei;

		depositXVault(user1, amount1);

		Request[] memory requests = new Request[](3);
		requests[0] = Request(address(nephewVault), amount1);
		requests[1] = Request(address(childVault), amount2);
		requests[2] = Request(address(childVault), amount3);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount1 + amount2 + amount3, 0, 0, false);

		// localDeposit, crossDeposit, pending, received, message sent, assert on
		xvaultHarvestVault(
			childVault.balanceOf(address(xVault)),
			nephewVault.balanceOf(address(xVault)),
			1,
			0,
			1,
			true
		);
	}

	// // More variations on that (no messages for example)

	function testOneChainFinalizeHarvest() public {
		// uint256 amount = 1 ether;

		// depositXVault(user1, amount);

		// Request[] memory requests = new Request[](1);
		// requests[0] = Request(address(nephewVault), amount);

		// // Requests, total amount deposited, expected msgSent events, expected bridge events
		// xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		// // This part is to fake a cross deposit into a vault
		// // Fake a receive message on destination
		// vm.startPrank(address(postmanLz));
		// nephewVault.receiveMessage(
		// 	Message(amount, address(xVault), address(0), chainId),
		// 	messageType.DEPOSIT
		// );
		// vm.stopPrank();

		// // Fake that funds arrive after a bridge
		// vm.deal(address(nephewVault), amount);
		// vm.startPrank(address(nephewVault));
		// // Get some ERC20 for vault
		// underlying.deposit{ value: amount }();
		// vm.stopPrank();

		// // Manager process incoming funds
		// vm.startPrank(manager);
		// nephewVault.processIncomingXFunds();
		// vm.stopPrank();

		// // Go back to harvest test
		// // localDeposit, crossDeposit, pending, received, message sent, assert on
		// xvaultHarvestVault(0, 0, 0, 0, 0, false);

		// // Fake return from cross child vault
		// vm.startPrank(address(postmanLz));
		// xVault.receiveMessage(
		// 	Message(
		// 		nephewVault.underlyingBalance(address(xVault)),
		// 		address(nephewVault),
		// 		address(0),
		// 		anotherChainId
		// 	),
		// 	messageType.HARVEST
		// );
		// vm.stopPrank();

		// vm.prank(manager);
		// xVault.finalizeHarvest(amount, 0);

		// // Calculate somehow expectedValue and maxDelta
		// assertEq(xVault.totalChildHoldings(), amount, "Harvest was updated value.");
		// (uint256 lDeposit, uint256 cDeposit, uint256 pAnswers, uint256 rAnswers) = xVault
		// 	.harvestLedger();
		// assertEq(lDeposit, 0, "No more info on harvest Ledger");
		// assertEq(cDeposit, 0, "No more info on harvest Ledger");
		// assertEq(pAnswers, 0, "No more info on harvest Ledger");
		// assertEq(rAnswers, 0, "No more info on harvest Ledger");
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		address[] memory vaults = new address[](2);
		vaults[0] = address(childVault);
		vaults[1] = address(nephewVault);

		uint[] memory amounts = new uint[](2);
		amounts[0] = amount;
		amounts[1] = 0;
		xvaultFinalizeHarvest(vaults, amounts);
	}

	// // More variations on that (no messages for example)
	function testOneCrossFinalizeHarvest() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0, false);

		address[] memory vaults = new address[](1);
		vaults[0] = address(nephewVault);

		uint[] memory amounts = new uint[](1);
		amounts[0] = amount;
		xvaultFinalizeHarvest(vaults, amounts);
	}

	// // Assert errors

	// function testOneChainEmergencyWithdrawVaults() public {

	// }
	// function testOneCrossEmergencyWithdrawVaults() public {

	// }
	// function testMultipleEmergencyWithdrawVaults() public {

	// }

	// // Passive calls (receive message)

	// function testReceiveWithdraw() public {

	// }

	// function testReceiveHarvest() public {

	// }

	// // XChain part (also vault management)

	// function testAddVault() public {

	// }

	// function testRemoveVault() public {

	// }

	// function testChangeVaultStatus() public {

	// }

	// function testUpdateVaultPostman() public {

	// }

	// function testManagePostman() public {

	// }

	// function testSendToken() public {
	// 	// How?
	// }

	/* =============================== REFERENCE HELPER ============================= */
	// function testWithdraw() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);
	// 	uint256 shares = vault.balanceOf(user1);
	// 	sectInitRedeem(vault, user1, 1e18 / 4);

	// 	assertEq(vault.balanceOf(user1), (shares * 3) / 4, "3/4 of shares remains");

	// 	assertFalse(vault.redeemIsReady(user1), "redeem not ready");

	// 	vm.expectRevert(BatchedWithdraw.NotReady.selector);
	// 	vm.prank(user1);
	// 	vault.redeem();

	// 	sectHarvest(vault);

	// 	assertTrue(vault.redeemIsReady(user1), "redeem ready");
	// 	sectCompleteRedeem(vault, user1);
	// 	assertEq(vault.underlyingBalance(user1), (100e18 * 3) / 4, "3/4 of deposit remains");

	// 	assertEq(underlying.balanceOf(user1), amnt / 4);

	// 	// amount should reset
	// 	vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
	// 	vm.prank(user1);
	// 	vault.redeem();
	// }

	// function testWithdrawAfterProfit() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);

	// 	// funds deposited
	// 	depositToStrat(strategy1, amnt);
	// 	underlying.mint(address(strategy1), 10e18); // 10% profit

	// 	sectInitRedeem(vault, user1, 1e18 / 4);

	// 	sectHarvestRevert(vault, SectorBase.NotEnoughtFloat.selector);

	// 	withdrawFromStrat(strategy1, amnt / 4);

	// 	sectHarvest(vault);

	// 	vm.prank(user1);
	// 	assertApproxEqAbs(vault.getPenalty(), .09e18, mLp);

	// 	sectCompleteRedeem(vault, user1);

	// 	assertEq(underlying.balanceOf(user1), amnt / 4);
	// }

	// function testWithdrawAfterLoss() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);

	// 	// funds deposited
	// 	depositToStrat(strategy1, amnt);
	// 	underlying.burn(address(strategy1.strategy()), 10e18); // 10% loss

	// 	sectInitRedeem(vault, user1, 1e18 / 4);

	// 	withdrawFromStrat(strategy1, amnt / 4);

	// 	sectHarvest(vault);

	// 	vm.prank(user1);
	// 	assertEq(vault.getPenalty(), 0);

	// 	sectCompleteRedeem(vault, user1);

	// 	assertApproxEqAbs(underlying.balanceOf(user1), (amnt * .9e18) / 4e18, mLp);
	// }

	// function testCancelWithdraw() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt / 4);
	// 	sectDeposit(vault, user2, (amnt * 3) / 4);

	// 	// funds deposited
	// 	depositToStrat(strategy1, amnt);
	// 	underlying.mint(address(strategy1), 10e18 + (mLp) / 10); // 10% profit

	// 	sectInitRedeem(vault, user1, 1e18);
	// 	sectHarvestRevert(vault, SectorBase.NotEnoughtFloat.selector);

	// 	withdrawFromStrat(strategy1, amnt / 4);
	// 	sectHarvest(vault);

	// 	vm.prank(user1);
	// 	vault.cancelRedeem();

	// 	uint256 profit = ((10e18 + (mLp) / 10) * 9) / 10;
	// 	uint256 profitFromBurn = (profit / 4) / 4;
	// 	assertApproxEqAbs(vault.underlyingBalance(user1), amnt / 4 + profitFromBurn, .1e18);
	// 	assertEq(underlying.balanceOf(user1), 0);

	// 	// amount should reset
	// 	vm.expectRevert(BatchedWithdraw.ZeroAmount.selector);
	// 	vm.prank(user1);
	// 	vault.redeem();
	// }

	// function testDepositWithdrawStrats() public {
	// 	uint256 amnt = 1000e18;
	// 	sectDeposit(vault, user1, amnt - mLp);

	// 	sectDeposit3Strats(vault, 200e18, 300e18, 500e18);

	// 	assertEq(vault.getTvl(), amnt);
	// 	assertEq(vault.totalChildHoldings(), amnt);

	// 	sectRedeem3Strats(vault, 200e18 / 2, 300e18 / 2, 500e18 / 2);

	// 	assertEq(vault.getTvl(), amnt);
	// 	assertEq(vault.totalChildHoldings(), amnt / 2);
	// }

	// function testFloatAccounting() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);

	// 	assertEq(vault.floatAmnt(), amnt + mLp);

	// 	depositToStrat(strategy1, amnt);

	// 	assertEq(vault.floatAmnt(), mLp);

	// 	sectInitRedeem(vault, user1, 1e18 / 2);

	// 	withdrawFromStrat(strategy1, amnt / 2);

	// 	assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float");
	// 	assertEq(vault.pendingWithdraw(), amnt / 2, "pending withdraw");
	// 	sectHarvest(vault);
	// 	assertEq(vault.floatAmnt(), amnt / 2 + mLp, "float amnt half");

	// 	DepositParams[] memory dParams = new DepositParams[](1);
	// 	dParams[0] = (DepositParams(strategy1, amnt / 2, 0));
	// 	vm.expectRevert(SectorBase.NotEnoughtFloat.selector);
	// 	vault.depositIntoStrategies(dParams);

	// 	vm.prank(user1);
	// 	vault.redeem();
	// 	assertEq(vault.floatAmnt(), mLp);
	// }

	// function testPerformanceFee() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);

	// 	depositToStrat(strategy1, amnt);
	// 	underlying.mint(address(strategy1), 10e18 + (mLp) / 10); // 10% profit

	// 	uint256 expectedTvl = vault.getTvl();
	// 	assertEq(expectedTvl, 110e18 + mLp);

	// 	sectHarvest(vault);

	// 	assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
	// 	assertApproxEqAbs(vault.underlyingBalance(user1), 109e18, mLp);
	// }

	// function testManagementFee() public {
	// 	uint256 amnt = 100e18;
	// 	sectDeposit(vault, user1, amnt);
	// 	vault.setManagementFee(.01e18);

	// 	depositToStrat(strategy1, amnt);

	// 	skip(365 days);
	// 	sectHarvest(vault);

	// 	assertApproxEqAbs(vault.underlyingBalance(treasury), 1e18, mLp);
	// 	assertApproxEqAbs(vault.underlyingBalance(user1), 99e18, mLp);
	// }

	// function testEmergencyRedeem() public {
	// 	uint256 amnt = 1000e18;
	// 	sectDeposit(vault, user1, amnt);
	// 	sectDeposit3Strats(vault, 200e18, 300e18, 400e18);
	// 	skip(1);
	// 	vm.startPrank(user1);
	// 	vault.emergencyRedeem();

	// 	assertApproxEqAbs(underlying.balanceOf(user1), 100e18, mLp, "recovered float");

	// 	uint256 b1 = IERC20(address(strategy1)).balanceOf(user1);
	// 	uint256 b2 = IERC20(address(strategy2)).balanceOf(user1);
	// 	uint256 b3 = IERC20(address(strategy3)).balanceOf(user1);

	// 	strategy1.redeem(user1, b1, address(underlying), 0);
	// 	strategy2.redeem(user1, b2, address(underlying), 0);
	// 	strategy3.redeem(user1, b3, address(underlying), 0);

	// 	assertApproxEqAbs(underlying.balanceOf(user1), amnt, 1, "recovered amnt");
	// 	assertApproxEqAbs(vault.getTvl(), mLp, 1);
	// }

	// /// UTILS

	// function depositToStrat(ISCYStrategy strategy, uint256 amount) public {
	// 	DepositParams[] memory params = new DepositParams[](1);
	// 	params[0] = (DepositParams(strategy, amount, 0));
	// 	vault.depositIntoStrategies(params);
	// }

	// function withdrawFromStrat(ISCYStrategy strategy, uint256 amount) public {
	// 	RedeemParams[] memory rParams = new RedeemParams[](1);
	// 	rParams[0] = (RedeemParams(strategy, amount, 0));
	// 	vault.withdrawFromStrategies(rParams);
	// }

	// function sectHarvest(SectorVault _vault) public {
	// 	vm.startPrank(manager);
	// 	uint256 expectedTvl = vault.getTvl();
	// 	uint256 maxDelta = expectedTvl / 1000; // .1%
	// 	_vault.harvest(expectedTvl, maxDelta);
	// 	vm.stopPrank();
	// }

	// function sectHarvestRevert(SectorVault _vault, bytes4 err) public {
	// 	vm.startPrank(manager);
	// 	uint256 expectedTvl = vault.getTvl();
	// 	uint256 maxDelta = expectedTvl / 1000; // .1%
	// 	vm.expectRevert(err);
	// 	_vault.harvest(expectedTvl, maxDelta);
	// 	vm.stopPrank();
	// 	// advance 1s
	// }

	// function sectDeposit(
	// 	SectorVault _vault,
	// 	address acc,
	// 	uint256 amnt
	// ) public {
	// 	MockERC20 _underlying = MockERC20(address(_vault.underlying()));
	// 	vm.startPrank(acc);
	// 	_underlying.approve(address(_vault), amnt);
	// 	_underlying.mint(acc, amnt);
	// 	_vault.deposit(amnt, acc);
	// 	vm.stopPrank();
	// }

	// function sectInitRedeem(
	// 	SectorVault _vault,
	// 	address acc,
	// 	uint256 fraction
	// ) public {
	// 	vm.startPrank(acc);
	// 	uint256 sharesToWithdraw = (_vault.balanceOf(acc) * fraction) / 1e18;
	// 	_vault.requestRedeem(sharesToWithdraw);
	// 	vm.stopPrank();
	// 	// advance 1s to ensure we don't have =
	// 	skip(1);
	// }

	// function sectCompleteRedeem(SectorVault _vault, address acc) public {
	// 	vm.startPrank(acc);
	// 	_vault.redeem();
	// 	vm.stopPrank();
	// }

	// function sectDeposit3Strats(
	// 	SectorVault _vault,
	// 	uint256 a1,
	// 	uint256 a2,
	// 	uint256 a3
	// ) public {
	// 	DepositParams[] memory dParams = new DepositParams[](3);
	// 	dParams[0] = (DepositParams(strategy1, a1, 0));
	// 	dParams[1] = (DepositParams(strategy2, a2, 0));
	// 	dParams[2] = (DepositParams(strategy3, a3, 0));
	// 	_vault.depositIntoStrategies(dParams);
	// }

	// function sectRedeem3Strats(
	// 	SectorVault _vault,
	// 	uint256 a1,
	// 	uint256 a2,
	// 	uint256 a3
	// ) public {
	// 	RedeemParams[] memory rParams = new RedeemParams[](3);
	// 	rParams[0] = (RedeemParams(strategy1, a1, 0));
	// 	rParams[1] = (RedeemParams(strategy2, a2, 0));
	// 	rParams[2] = (RedeemParams(strategy3, a3, 0));
	// 	_vault.withdrawFromStrategies(rParams);
	// }
}
