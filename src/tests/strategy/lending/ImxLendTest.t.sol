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

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract ImxLendTest is IntegrationTest, UnitTestVault {
	using stdJson for string;

	string TEST_STRATEGY = "LND_USDC-ETH_Tarot_optimism";
	// string TEST_STRATEGY = "LND_ETH-USDC_Tarot_optimism";

	// string TEST_STRATEGY = "LND_USDC-ETH_Tarot_arbitrum";
	// string TEST_STRATEGY = "LND_ETH-USDC_Tarot_arbitrum";

	SCYVaultConfig vaultConfig;
	IMXLendStrategy strategy;

	uint256 currentFork;

	struct StratConfJSON {
		address a_underlying;
		address b_strategy;
		bool c_acceptsNativeToken;
		string x_chain;
	}

	// TODO we can return a full array for a given chain
	// and test all strats...
	function getConfig(string memory symbol) public {
		string memory root = vm.projectRoot();
		string memory path = string.concat(root, "/ts/config/strategies.json");
		string memory json = vm.readFile(path);
		// bytes memory names = json.parseRaw(".strats");
		// string[] memory strats = abi.decode(names, (string[]));
		bytes memory strat = json.parseRaw(string.concat(".", symbol));
		StratConfJSON memory stratJson = abi.decode(strat, (StratConfJSON));

		vaultConfig.underlying = IERC20(stratJson.a_underlying);
		vaultConfig.yieldToken = stratJson.b_strategy; // collateral token
		vaultConfig.maxTvl = type(uint128).max;
		vaultConfig.acceptsNativeToken = stratJson.c_acceptsNativeToken;

		string memory RPC_URL = vm.envString(string.concat(stratJson.x_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.x_chain, "_BLOCK"));

		currentFork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(currentFork);
	}

	function setUp() public {
		getConfig(TEST_STRATEGY);

		/// todo should be able to do this via address and mixin
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";

		underlying = IERC20(address(vaultConfig.underlying));

		vault = deploySCYVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, .1e18, 0),
			vaultConfig
		);

		strategy = new IMXLendStrategy(address(vault), vaultConfig.yieldToken);
		vault.initStrategy(address(strategy));

		underlying.approve(address(vault), type(uint256).max);

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
