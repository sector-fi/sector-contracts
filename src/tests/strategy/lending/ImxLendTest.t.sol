// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";

import { IMXConfig, HarvestSwapParams } from "interfaces/Structs.sol";
import { IMXLendStrategy } from "strategies/lending/IMXLendStrategy.sol";
import { IMX } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IntegrationTest } from "../common/IntegrationTest.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";

import { SCYVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import "hardhat/console.sol";

contract ImxLendTest is IntegrationTest, UnitTestVault {
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	SCYVaultConfig vaultConfig;

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
	IERC20 avax = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

	address pool = 0x3b611a8E02908607c409b382D5671e8b3e39755d;
	address poolEth = 0xBE48d2910a8908d33A1fE11d4F156eEf87ED563c;

	IMXLendStrategy strategy;

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		/// todo should be able to do this via address and mixin
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = pool;
		vaultConfig.underlying = IERC20(address(usdc));
		vaultConfig.maxTvl = type(uint128).max;

		underlying = IERC20(address(vaultConfig.underlying));

		vault = new SCYVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, .1e18, 0),
			vaultConfig
		);

		strategy = new IMXLendStrategy(address(vault), pool);
		vault.initStrategy(address(strategy));

		usdc.approve(address(vault), type(uint256).max);

		configureUtils(address(vaultConfig.underlying), address(strategy));

		mLp = vault.MIN_LIQUIDITY();
		mLp = vault.sharesToUnderlying(mLp);
	}

	function rebalance() public override {}

	function harvest() public override {
		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		params1[0] = harvestParams;
		params1[0].min = 0;
		params1[0].deadline = block.timestamp + 1;
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
		uint256 tvl = vault.getTvl();
		(uint256[] memory harvestAmnts, ) = vault.harvest(tvl, tvl / 1000, params1, params2);
		// IMX Lend doesn't earn anything
		assertEq(harvestAmnts.length, 0);
	}

	function noRebalance() public override {}

	function adjustPrice(uint256 fraction) public override {}
}
