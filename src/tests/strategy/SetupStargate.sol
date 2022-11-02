// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";
import { SCYVault, Stargate, FarmConfig, Strategy, AuthConfig, FeeConfig } from "vaults/strategyVaults/Stargate.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StratUtils } from "./StratUtils.sol";
import { IStarchef } from "interfaces/stargate/IStarchef.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract SetupStargate is SectorTest, StratUtils {
	using stdJson for string;

	string TEST_STRATEGY = "USDC-Arbitrum-Stargate";

	uint256 currentFork;

	Strategy strategyConfig;
	FarmConfig farmConfig;

	Stargate strategy;

	struct StargateConfigJSON {
		address a_underlying;
		address b_strategy;
		uint16 c_strategyId;
		address d_yieldToken;
		uint16 e_farmId;
		address f1_farm;
		address f2_farmToken;
		address g_farmRouter;
		bytes h_harvestPath;
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
		StargateConfigJSON memory stratJson = abi.decode(strat, (StargateConfigJSON));

		strategyConfig.underlying = IERC20(stratJson.a_underlying);
		strategyConfig.yieldToken = stratJson.d_yieldToken; // collateral token
		strategyConfig.addr = stratJson.b_strategy;
		strategyConfig.strategyId = stratJson.c_strategyId;
		strategyConfig.maxTvl = type(uint128).max;

		farmConfig = FarmConfig({
			farmId: stratJson.e_farmId,
			farm: stratJson.f1_farm,
			farmToken: stratJson.f2_farmToken,
			router: stratJson.g_farmRouter
		});

		harvestParams.pathData = stratJson.h_harvestPath;

		string memory RPC_URL = vm.envString(string.concat(stratJson.x_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.x_chain, "_BLOCK"));

		currentFork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(currentFork);
	}

	function setUp() public {
		getConfig(TEST_STRATEGY);

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";

		underlying = IERC20(address(strategyConfig.underlying));

		vault = SCYVault(
			new Stargate(
				AuthConfig(owner, guardian, manager),
				FeeConfig(treasury, .1e18, 0),
				strategyConfig,
				farmConfig
			)
		);

		underlying.approve(address(vault), type(uint256).max);

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

	function harvest() public override {
		// if (!strategy.harvestIsEnabled()) return;
		skip(7 * 60 * 60 * 24);
		vm.roll(block.number + 1000);

		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		params1[0] = harvestParams;
		params1[0].min = 0;
		params1[0].deadline = block.timestamp + 1;
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

		uint256 tvl = vault.getAndUpdateTvl();
		(uint256[] memory harvestAmnts, ) = vault.harvest(vault.getTvl(), 0, params1, params2);
		uint256 newTvl = vault.getTvl();

		assertGt(harvestAmnts[0], 0);
		assertGt(newTvl, tvl);
	}

	function noRebalance() public override {}

	function adjustPrice(uint256 fraction) public override {}
}
