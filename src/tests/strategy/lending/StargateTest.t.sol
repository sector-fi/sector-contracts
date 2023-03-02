// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";

import { HarvestSwapParams } from "interfaces/Structs.sol";
import { StargateStrategy, FarmConfig } from "strategies/lending/StargateStrategy.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStarchef } from "interfaces/stargate/IStarchef.sol";

import { IntegrationTest } from "../common/IntegrationTest.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";

import { SCYVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract StargateTest is IntegrationTest, UnitTestVault {
	using stdJson for string;

	// string TEST_STRATEGY = "LND_USDC_Stargate_arbitrum";
	string TEST_STRATEGY = "LND_ETH_Stargate_arbitrum";

	uint256 currentFork;

	SCYVaultConfig vaultConfig;
	FarmConfig farmConfig;

	StargateStrategy strategy;
	address stargateRouter;

	struct StargateConfigJSON {
		address a_underlying;
		address b_strategy;
		uint16 c_strategyId;
		address d1_yieldToken;
		bool d2_acceptsNativeToken;
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

		vaultConfig.underlying = IERC20(stratJson.a_underlying);
		vaultConfig.yieldToken = stratJson.d1_yieldToken; // collateral token
		vaultConfig.strategyId = stratJson.c_strategyId;
		vaultConfig.maxTvl = type(uint128).max;
		vaultConfig.acceptsNativeToken = stratJson.d2_acceptsNativeToken;

		stargateRouter = stratJson.b_strategy;

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
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";

		underlying = IERC20(address(vaultConfig.underlying));

		vault = deploySCYVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, .1e18, 0),
			vaultConfig
		);

		strategy = new StargateStrategy(
			address(vault),
			vaultConfig.yieldToken,
			stargateRouter,
			vaultConfig.strategyId,
			farmConfig
		);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);

		configureUtils(address(vaultConfig.underlying), address(strategy));
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

	function testDeploymentHarvest() public {
		// SCYVault dStrat = SCYVault(payable(0x596777F4a395e4e4dE3501858bE9719859C2F64D));
		SCYVault dStrat = SCYVault(payable(0xD626992d6754b358bc36F4B3eec9fb2B2Ba2DF38));

		skip(7 * 60 * 60 * 24);
		vm.roll(block.number + 100000);

		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		params1[0] = harvestParams;
		params1[0].min = 0;
		params1[0].deadline = block.timestamp + 1;
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

		// uint256 tvl = dStrat.getAndUpdateTvl();
		uint256 tvl = dStrat.getTvl();
		vm.prank(0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A);
		(uint256[] memory harvestAmnts, ) = dStrat.harvest(tvl, 0, params1, params2);
		console.log("harvest", harvestAmnts[0]);

		uint256 amount = 30e6;
		deal(address(dStrat.underlying()), self, 30e6);
		uint256 minSharesOut = dStrat.underlyingToShares(amount);
		vm.startPrank(self);
		underlying.approve(address(vault), amount);
		vault.deposit(self, address(underlying), amount, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		console.log(vault.underlyingBalance(self));
		assertApproxEqRel(vault.underlyingBalance(self), amount, .001e18);

		// vm.startPrank(0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A);
		// HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		// params1[0] = harvestParams;
		// params1[0].min = 0;
		// params1[0].deadline = block.timestamp + 1;
		// HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

		// uint256 tvl = dStrat.getAndUpdateTvl();
		// (uint256[] memory harvestAmnts, ) = dStrat.harvest(dStrat.getTvl(), 0, params1, params2);
		// vm.stopPrank();
		// assertGt(harvestAmnts[0], 0);
	}
}
