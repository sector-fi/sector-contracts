// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { IMXUtils, UniUtils, IUniswapV2Pair } from "../utils/IMXUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { IMXVault, Strategy } from "../../vaults/IMXVault.sol";
import { Bank, Pool } from "../../bank/Bank.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "hardhat/console.sol";

contract IMXSetup is SectorTest, IMXUtils, ERC1155Holder {
	using UniUtils for IUniswapV2Pair;

	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	Bank bank;
	IMXVault vault;
	IMX strategy;

	IMXConfig config;
	HarvestSwapParms harvestParams;

	address manager = address(1);
	address guardian = address(2);
	address treasury = address(3);
	address owner = address(this);
	Strategy strategyConfig;
	uint96 stratId;

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
		config.farmRouter = 0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
		config.maxTvl = type(uint128).max;
		config.owner = owner;
		config.manager = manager;
		config.guardian = guardian;

		bank = new Bank("api.sector.finance/<id>.json", address(this), guardian, manager, treasury);

		vault = new IMXVault();
		vault.initialize(address(bank), owner, guardian, manager, treasury);

		config.vault = address(vault);

		strategy = new IMX();
		strategy.initialize(config);

		/// todo should be able to do this via address and mixin
		strategyConfig.addr = address(strategy);
		strategyConfig.yieldToken = config.poolToken;
		strategyConfig.underlying = IERC20Upgradeable(config.underlying);
		strategyConfig.maxTvl = uint128(config.maxTvl);
		strategyConfig.exists = true;
		stratId = vault.addStrategy(strategyConfig);

		usdc.approve(address(vault), type(uint256).max);

		bank.addPool(
			Pool({
				vault: address(vault),
				id: stratId,
				exists: true,
				decimals: usdc.decimals(),
				managementFee: 1000 // 10%
			})
		);
	}

	function deposit(uint256 amount) public {
		uint256 startTvl = strategy.getTotalTVL();
		deal(address(usdc), address(this), amount);
		// TODO use min amount
		vault.deposit(stratId, address(this), address(usdc), amount, 0);
		uint256 tvl = strategy.getTotalTVL();
		assertApproxEqAbs(tvl, startTvl + amount, 10);
		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 vaultBalance = IERC20(vault.yieldToken(stratId)).balanceOf(address(strategy));
		assertEq(bank.balanceOf(address(this), token), vaultBalance);
		assertEq(vault.underlyingBalance(stratId, address(this)), tvl);
	}

	function withdraw(uint256 fraction) public {
		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 balance = bank.balanceOf(address(this), token);
		vault.redeem(stratId, address(this), (balance * fraction) / 1e18, address(usdc), 0);
	}

	function adjustPrice(uint256 fraction) public {
		address oracle = ICollateral(config.poolToken).simpleUniswapOracle();
		address stakedToken = ICollateral(config.poolToken).underlying();
		movePrice(config.uniPair, stakedToken, config.underlying, config.short, oracle, fraction);
	}

	function rebalance() public {
		assertGt(strategy.getPositionOffset(), strategy.rebalanceThreshold());
		strategy.rebalance();
		assertEq(strategy.getPositionOffset(), 0);
	}
}
