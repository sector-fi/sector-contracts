// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { IMXUtils, UniUtils, IUniswapV2Pair } from "../utils/IMXUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { IMXLend, Strategy } from "../../vaults/IMXLend.sol";
import { Bank, Pool } from "../../bank/Bank.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "hardhat/console.sol";

contract IMXLending is SectorTest, IMXUtils, ERC1155Holder {
	using UniUtils for IUniswapV2Pair;

	uint256 BASIS = 10000;
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	Bank bank;
	IMXLend vault;

	IMXConfig config;
	HarvestSwapParms harvestParams;

	address manager = address(1);
	address guardian = address(2);
	address treasury = address(3);
	address owner = address(this);
	Strategy strategyConfig;
	uint96 stratId;

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
	IERC20 avax = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

	address strategy = 0x3b611a8E02908607c409b382D5671e8b3e39755d;
	address strategyEth = 0xBE48d2910a8908d33A1fE11d4F156eEf87ED563c;

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		bank = new Bank("api.sector.finance/<id>.json", address(this), guardian, manager, treasury);

		vault = new IMXLend();
		vault.initialize(address(bank), owner, guardian, manager, treasury);

		config.vault = address(vault);

		/// todo should be able to do this via address and mixin
		strategyConfig.addr = address(strategy);
		strategyConfig.yieldToken = address(strategy);
		strategyConfig.underlying = IERC20Upgradeable(address(usdc));
		strategyConfig.maxTvl = type(uint128).max;
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

	function testDeposit() public {
		deposit(1000e6);
	}

	function testWithdraw() public {
		deposit(1000e6);
		withdrawCheck(.4e18);
	}

	function deposit(uint256 amount) public {
		uint256 startTvl = vault.getStrategyTvl(stratId);
		deal(address(usdc), address(this), amount);
		uint256 minSharesOut = vault.underlyingToShares(stratId, amount);
		vault.deposit(stratId, address(this), address(usdc), amount, (minSharesOut * 9990) / 10000);
		uint256 tvl = vault.getStrategyTvl(stratId);
		assertApproxEqAbs(tvl, startTvl + amount, 10, "tvl should be correct");
		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 vaultBalance = IERC20(vault.yieldToken(stratId)).balanceOf(address(vault));
		assertEq(
			bank.balanceOf(address(this), token),
			vaultBalance,
			"vault balance should match user"
		);
		assertEq(
			vault.underlyingBalance(stratId, address(this)),
			tvl,
			"underlying balance should match tvl"
		);
	}

	function withdraw(uint256 fraction) public {
		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 sharesToWithdraw = (bank.balanceOf(address(this), token) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(stratId, sharesToWithdraw);
		vault.redeem(
			stratId,
			address(this),
			sharesToWithdraw,
			address(usdc),
			(minUnderlyingOut * 9990) / 10000
		);
	}

	function withdrawCheck(uint256 fraction) public {
		uint256 startTvl = vault.getStrategyTvl(stratId);
		withdraw(fraction);

		uint256 token = bank.getTokenId(address(vault), 0);
		uint256 tvl = vault.getStrategyTvl(stratId);
		assertApproxEqAbs(tvl, (startTvl * (1e18 - fraction)) / 1e18, 10);
		uint256 vaultBalance = IERC20(vault.yieldToken(stratId)).balanceOf(address(vault));
		assertApproxEqAbs(bank.balanceOf(address(this), token), vaultBalance, 10);
		assertApproxEqAbs(vault.underlyingBalance(stratId, address(this)), tvl, 10);
	}
}
