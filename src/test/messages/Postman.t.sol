// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { LayerZeroPostman, chainPair } from "../../xChain/LayerZeroPostman.sol";
import { MultichainPostman } from "../../xChain/MultichainPostman.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SectorXVaultSetup } from "../vault/SectorXVaultSetup.t.sol";
import { SectorXVault } from "vaults/sectorVaults/SectorXVault.sol";
import { SectorVault, AuthConfig, FeeConfig } from "vaults/sectorVaults/SectorVault.sol";
import { SCYVaultSetup } from "../vault/SCYVaultSetup.sol";
import { WETH } from "../mocks/WETH.sol";
import "interfaces/MsgStructs.sol";
import "forge-std/Vm.sol";

import "hardhat/console.sol";

contract PostmanTest is SectorXVaultSetup, SCYVaultSetup {
	LayerZeroPostman EthLZpostman;
	LayerZeroPostman AvaxLZpostman;
	MultichainPostman AvaxMCpostman;
	MultichainPostman EthMCpostman;
	SectorVault EthSectorVault;
	SectorVault AvaxSectorVault;

	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	string ETH_RPC_URL = vm.envString("ETH_RPC_URL");
	uint16 AVAX_CHAIN_ID = 43114;
	uint16 AVAX_LAYERZERO_ID = 106;
	uint16 ETHEREUM_CHAIN_ID = 1;
	uint16 ETHEREUM_LAYERZERO_ID = 101;
	address AVAX_LAYERZERO_ENDPOINT = 0x3c2269811836af69497E5F486A85D7316753cf62;
	address ETH_LAYERZERO_ENDPOINT = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
	address MULTICHAIN_ENDPOINT = 0xC10Ef9F491C9B59f936957026020C321651ac078;
	uint256 avaxFork;
	uint256 ethFork;

	event MessageReceived(
		address srcVaultAddress,
		uint256 amount,
		address dstVaultAddress,
		uint16 messageType,
		uint256 srcChainId
	);

	event RegisterIncomingFunds(uint256 total);

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, 21148939);
		ethFork = vm.createFork(ETH_RPC_URL, 15790742);

		chainPair[] memory pairArray = new chainPair[](2);
		pairArray[0] = chainPair(AVAX_CHAIN_ID, AVAX_LAYERZERO_ID);
		pairArray[1] = chainPair(ETHEREUM_CHAIN_ID, ETHEREUM_LAYERZERO_ID);

		vm.selectFork(ethFork);

		underlying = new WETH();

		EthSectorVault = new SectorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			1e14
		);

		EthLZpostman = new LayerZeroPostman(ETH_LAYERZERO_ENDPOINT, pairArray, manager);

		EthMCpostman = new MultichainPostman(MULTICHAIN_ENDPOINT, manager);

		vm.deal(address(manager), 100 ether);

		vm.selectFork(avaxFork);

		AvaxSectorVault = new SectorVault(
			underlying,
			"SECT_VAULT",
			"SECT_VAULT",
			false,
			3 days,
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, DEFAULT_PERFORMANCE_FEE, DEAFAULT_MANAGEMENT_FEE),
			1e14
		);

		AvaxLZpostman = new LayerZeroPostman(AVAX_LAYERZERO_ENDPOINT, pairArray, manager);

		AvaxMCpostman = new MultichainPostman(MULTICHAIN_ENDPOINT, manager);

		vm.deal(address(manager), 100 ether);
	}

	// Test if LayerZero message goes through
	// and if manager is refunded for the extra value sent
	function testSendLzMessage() public {
		address _srcVault = address(AvaxSectorVault);
		address _dstVault = address(EthSectorVault);
		address _dstPostman = address(EthLZpostman);

		Message memory _msg = Message(1000, _srcVault, address(0), AVAX_CHAIN_ID);

		vm.startPrank(manager);

		uint256 _amountBefore = manager.balance;

		uint256 messageFee = AvaxLZpostman.estimateFee(
			ETHEREUM_CHAIN_ID,
			_dstVault,
			MessageType.DEPOSIT,
			_msg
		);

		AvaxLZpostman.deliverMessage{ value: 2 ether }(
			_msg,
			_dstVault,
			_dstPostman,
			MessageType.DEPOSIT,
			ETHEREUM_CHAIN_ID
		);

		uint256 _amountAfter = manager.balance;

		uint256 diff = _amountBefore - _amountAfter;

		assertEq(true, diff == messageFee);

		vm.stopPrank();
	}

	// Test if MultiChain message goes through
	// and if manager is refunded for the extra value sent
	function testSendMcMessage() public {
		address _srcVault = address(AvaxSectorVault);
		address _dstVault = address(EthSectorVault);
		address _dstPostman = address(EthMCpostman);

		Message memory _msg = Message(1000, _srcVault, address(0), AVAX_CHAIN_ID);

		vm.startPrank(manager);

		uint256 _amountBefore = manager.balance;

		uint256 messageFee = AvaxMCpostman.estimateFee(
			ETHEREUM_CHAIN_ID,
			_dstVault,
			MessageType.DEPOSIT,
			_msg
		);

		AvaxMCpostman.deliverMessage{ value: 2 ether }(
			_msg,
			_dstVault,
			_dstPostman,
			MessageType.DEPOSIT,
			ETHEREUM_CHAIN_ID
		);

		uint256 _amountAfter = manager.balance;

		uint256 diff = _amountBefore - _amountAfter;

		assertEq(true, diff == messageFee);

		vm.stopPrank();
	}

	// Test if LayerZero message is received by the detination Postman
	// and if the destination vault register the message
	function testLzReceiveMessage() public {
		address _srcVault = address(AvaxSectorVault);
		address _dstVault = address(EthSectorVault);

		Message memory _msg = Message(1000, _srcVault, address(0), AVAX_CHAIN_ID);

		bytes memory _payload = abi.encode(_msg, _dstVault, MessageType.DEPOSIT);

		vm.selectFork(ethFork);

		EthSectorVault.managePostman(1, ETHEREUM_CHAIN_ID, address(EthLZpostman));
		EthSectorVault.addVault(_srcVault, AVAX_CHAIN_ID, 1, true);

		vm.startPrank(ETH_LAYERZERO_ENDPOINT);

		vm.expectEmit(true, true, false, true);
		emit MessageReceived(
			_srcVault,
			1000,
			_dstVault,
			uint16(MessageType.DEPOSIT),
			AVAX_CHAIN_ID
		);

		bytes memory mock = abi.encode(_srcVault);

		EthLZpostman.lzReceive(AVAX_LAYERZERO_ID, mock, 1, _payload);

		vm.stopPrank();

		vm.startPrank(manager);

		underlying.deposit{ value: 1000 }();
		underlying.transfer(address(EthSectorVault), 1000);

		vm.expectEmit(true, true, false, true);
		emit RegisterIncomingFunds(1000);

		EthSectorVault.processIncomingXFunds();
		address xSrcAddr = EthSectorVault.getXAddr(_srcVault, AVAX_CHAIN_ID);
		uint256 _srcVaultUnderlyingBalance = EthSectorVault.estimateUnderlyingBalance(xSrcAddr);

		assertEq(1000, _srcVaultUnderlyingBalance);

		vm.stopPrank();
	}

	// Test if Multichain message is received by the detination Postman
	// and if the destination vault register the message
	function testMcReceiveMessage() public {
		address _srcVault = address(AvaxSectorVault);
		address _dstVault = address(EthSectorVault);

		Message memory _msg = Message(1000, _srcVault, address(0), AVAX_CHAIN_ID);

		bytes memory _payload = abi.encode(_msg, _dstVault, MessageType.DEPOSIT);

		vm.selectFork(ethFork);

		EthSectorVault.managePostman(1, ETHEREUM_CHAIN_ID, address(EthMCpostman));
		EthSectorVault.addVault(_srcVault, AVAX_CHAIN_ID, 1, true);

		vm.startPrank(MULTICHAIN_ENDPOINT);

		vm.expectEmit(true, true, false, true);
		emit MessageReceived(
			_srcVault,
			1000,
			_dstVault,
			uint16(MessageType.DEPOSIT),
			AVAX_CHAIN_ID
		);

		EthMCpostman.anyExecute(_payload);

		vm.stopPrank();

		vm.startPrank(manager);

		underlying.deposit{ value: 1000 }();
		underlying.transfer(address(EthSectorVault), 1000);

		vm.expectEmit(true, true, false, true);
		emit RegisterIncomingFunds(1000);

		EthSectorVault.processIncomingXFunds();

		address xSrcAddr = EthSectorVault.getXAddr(_srcVault, AVAX_CHAIN_ID);
		uint256 _srcVaultUnderlyingBalance = EthSectorVault.estimateUnderlyingBalance(xSrcAddr);

		assertEq(1000, _srcVaultUnderlyingBalance);

		vm.stopPrank();
	}
}
