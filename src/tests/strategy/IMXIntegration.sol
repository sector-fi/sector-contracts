// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig } from "../../interfaces/Structs.sol";
import { SCYVault1155 } from "../../vaults/scy/SCYVault1155.sol";
import { Bank, Pool } from "../../bank/Bank.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract IMXIntegrationTest is SectorTest, ERC1155Holder {
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	Bank bank;
	SCYVault1155 vault;
	IMX strategy;

	IMXConfig config;

	address manager = address(1);
	address guardian = address(2);
	address treasury = address(3);
	address owner = address(this);

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);

	uint256 snapshot;

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		// TODO use JSON
		config.underlying = address(usdc);
		config.short = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
		config.uniPair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1;
		config.poolToken = 0xEE2A27B7c3165A5E2a3FEB113A77B26b46dB0baE;
		config.farmToken = 0xeA6887e4a9CdA1B77E70129E5Fba830CdB5cdDef;
		config.farmRouter = 0xefa94DE7a4656D787667C749f7E1223D71E9FD88;
		config.maxTvl = type(uint256).max;
		config.owner = owner;
		config.manager = manager;
		config.guardian = guardian;

		bank = new Bank("api.sector.finance/<id>.json", address(this), guardian, manager, treasury);

		vault = new SCYVault1155();
		vault.initialize(config.poolToken, address(bank), owner, guardian, manager, treasury);
		config.vault = address(vault);

		strategy = new IMX();
		strategy.initialize(config);

		vault.setStrategy(strategy);
		usdc.approve(address(vault), type(uint256).max);

		bank.addPool(
			Pool({
				id: 0,
				vault: address(vault),
				exists: true,
				decimals: usdc.decimals(),
				managementFee: 1000 // 10%
			})
		);
	}

	function testDeposit() public {
		uint256 amount = 100e6;
		deal(address(usdc), address(this), amount);
		// TODO use min amount
		vault.deposit(address(this), address(usdc), amount, 0);
		uint256 tvl = strategy.getTotalTVL();
		assertApproxEqAbs(tvl, amount, 10);
		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 vaultBalance = IERC20(vault.yieldToken()).balanceOf(address(strategy));
		assertEq(bank.balanceOf(address(this), token), vaultBalance);

		assertEq(vault.underlyingBalance(address(this)), tvl);
		// snapshot = vm.snapshot();
		state();
	}

	function state() public {
		vm.revertTo(snapshot);
		uint256 amount = 100e6;
		uint256 tvl = strategy.getTotalTVL();
		assertApproxEqAbs(tvl, amount, 100);
	}
}
