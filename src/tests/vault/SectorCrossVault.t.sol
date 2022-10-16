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

import "forge-std/console.sol";
import "forge-std/Vm.sol";

contract SectorCrossVaultTest is SectorCrossVaultTestSetup, SCYVaultSetup {
	// ISCYStrategy strategy1;
	// ISCYStrategy strategy2;
	// ISCYStrategy strategy3;

	uint256 mainnetFork;
	string MAINNET_RPC_URL = vm.envString("INFURA_COMPLETE_RPC");

	// uint16 chainId;

	// WETH underlying;

	// SectorCrossVault xVault;
	// SectorVault childVault;
	// SectorVault nephewVault;

	// LayerZeroPostman postmanLz;
	// MultichainPostman postmanMc;

	function setUp() public {
		// address avaxLzAddr = 0x3c2269811836af69497E5F486A85D7316753cf62;
		// address ethLzAddr = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
		Endpoint endpoint = new Endpoint(uint16(block.chainid));
		address ethLzAddr = address(endpoint);

		// vm.makePersistent(address(user1));
		// mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
		// vm.selectFork(mainnetFork);
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
		postmanLz = new LayerZeroPostman(ethLzAddr, inptChainPair);

		// Must be address of multichain service provider
		// This is breaking because in the constructor calls a function on proxy (executor)
		// postmanMc = new MultichainPostman(address(xVault));

		// // Config both vaults to use postmen
		xVault.managePostman(1, chainId, address(postmanLz));
		// xVault.managePostman(2, chainId, address(postmanMc));
		xVault.addVault(address(childVault), chainId, 1, true);
		// Pretend that is on other chain
		xVault.addVault(address(nephewVault), 5, 1, true);

		childVault.managePostman(1, chainId, address(postmanLz));
		// childVault.managePostman(2, chainId, address(postmanMc));
		childVault.addVault(address(xVault), chainId, 1, true);
		childVault.addVault(address(nephewVault), 5, 1, true);

		// Still not sure about this part yet
		nephewVault.managePostman(1, chainId, address(postmanLz));
		// nephewVault.managePostman(2, chainId, address(postmanMc));
		nephewVault.addVault(address(xVault), chainId, 1, true);
		nephewVault.addVault(address(childVault), chainId, 1, true);

		vm.deal(user1, 10 ether);
		vm.deal(manager, 10 ether);
		vm.deal(guardian, 10 ether);
		// Postman needs native to pay provider.
		vm.deal(address(postmanLz), 10 ether);
	}

	function testOneChainDepositIntoVaults() public {
		// Request(addr, amount);
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(childVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 0, 0);

		// assertEq(xVault.totalChildHoldings(), amount);
		// assertEq(childVault.underlyingBalance(address(xVault)), amount);
	}

	function testOneCrossDepositIntoVaults() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount);

		Request[] memory requests = new Request[](1);
		requests[0] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount, 1, 1);
	}

	function testMultipleDepositIntoVauls() public {
		uint256 amount = 1 ether;

		depositXVault(user1, amount * 2);

		Request[] memory requests = new Request[](2);
		requests[0] = Request(address(childVault), amount);
		requests[1] = Request(address(nephewVault), amount);

		// Requests, total amount deposited, expected msgSent events, expected bridge events
		xvaultDepositIntoVaults(requests, amount * 2, 1, 1);
	}

	// // Assert from deposit errors
	// // Not in addr book

	// function testOneChainWithdrawFromVaults() public {

	// }
	// function testOneCrossWithdrawFromVaults() public {

	// }
	// function testMultipleWithdrawFromVaults() public {

	// }

	// // Assert errors

	// function testOneChainHarvestVaults() public {

	// }
	// function testOneCrossHarvestVaults() public {

	// }
	// function testMultipleHarvestVaults() public {

	// }

	// // More variations on that (no messages for example)
	// function testFinalizeHarvest() public {

	// }

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
