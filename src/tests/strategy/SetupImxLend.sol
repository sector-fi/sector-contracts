// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { SCYVault, IMXLend, Strategy, AuthConfig, FeeConfig } from "../../vaults/IMXLend.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StratUtils } from "./StratUtils.sol";
import { IntegrationTest } from "./Integration.sol";

import "hardhat/console.sol";

contract SetupImxLend is SectorTest, StratUtils, IntegrationTest {
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	Strategy strategyConfig;

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
	IERC20 avax = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

	address strategy = 0x3b611a8E02908607c409b382D5671e8b3e39755d;
	address strategyEth = 0xBE48d2910a8908d33A1fE11d4F156eEf87ED563c;

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.addr = strategy;
		strategyConfig.yieldToken = strategy;
		strategyConfig.underlying = IERC20(address(usdc));
		strategyConfig.maxTvl = type(uint128).max;

		underlying = IERC20(address(strategyConfig.underlying));

		vault = SCYVault(
			new IMXLend(
				AuthConfig(owner, guardian, manager),
				FeeConfig(treasury, .1e18, 0),
				strategyConfig
			)
		);

		usdc.approve(address(vault), type(uint256).max);

		configureUtils(
			address(strategyConfig.underlying),
			address(0),
			address(0),
			address(strategy)
		);
		mLp = vault.MIN_LIQUIDITY();
		mLp = vault.sharesToUnderlying(mLp);
	}

	function rebalance() public override {}

	function harvest() public override {}

	function noRebalance() public override {}

	function adjustPrice(uint256 fraction) public override {}
}
