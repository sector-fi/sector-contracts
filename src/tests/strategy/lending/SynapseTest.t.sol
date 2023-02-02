// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { HarvestSwapParams } from "interfaces/Structs.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStarchef } from "interfaces/stargate/IStarchef.sol";

import { IntegrationTest } from "../common/IntegrationTest.sol";
import { UnitTestVault } from "../common/UnitTestVault.sol";

import { SynapseStrategy, FarmConfig } from "strategies/lending/SynapseStrategy.sol";
import { SCYVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";
import { Accounting } from "../../../common/Accounting.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract SynapseTest is IntegrationTest, UnitTestVault {
	using stdJson for string;

	string TEST_STRATEGY = "USDC-Arbitrum-Synapse";

	uint256 currentFork;

	SCYVaultConfig vaultConfig;
	FarmConfig farmConfig;

	SynapseStrategy strategy;
	uint256 pooledTokens;
	address synapsePool;

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

		vaultConfig.underlying = IERC20(stratJson.a_underlying);
		vaultConfig.yieldToken = stratJson.d_yieldToken; // collateral token
		vaultConfig.strategyId = stratJson.c_strategyId;
		vaultConfig.maxTvl = 10000000e6;

		synapsePool = stratJson.b_strategy;

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

		strategy = new SynapseStrategy(
			address(vault),
			vaultConfig.yieldToken,
			synapsePool,
			uint8(vaultConfig.strategyId),
			farmConfig
		);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);

		configureUtils(address(vaultConfig.underlying), address(strategy));
		mLp = vault.MIN_LIQUIDITY();
		mLp = Accounting(address(vault)).convertToAssets(mLp);
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

	function testDust() public {
		deposit(user1, 1000e6);
		deposit(user2, 1000e6);
		deposit(user3, 1000e6);
		harvest();

		// if we skip ahead in time, we will
		// be able to withdraw full tvl
		skip(7 * 60 * 60 * 24);

		withdraw(user1, 1e18);
		withdraw(user2, 1e18);
		withdraw(user3, 1e18);
		withdraw(treasury, 1e18);

		uint256 tvl = vault.getTvl();
		assertEq(tvl, 0);
	}

	function testSlippage() public {
		uint256 amount = 10000000e6;
		uint256 shares = vault.underlyingToShares(amount);
		uint256 actualShares = vault.getDepositAmnt(amount);
		assertGt(shares, actualShares);
		console.log("d slippage", (10000 * (shares - actualShares)) / shares);

		deposit(user1, getAmnt());

		// uint256 balance = vault.underlyingBalance(user1);
		// shares = vault.balanceOf(user1);
		uint256 wAmnt = 2000000e6;
		shares = vault.underlyingToShares(wAmnt);
		uint256 actualBalance = vault.getWithdrawAmnt(shares);
		assertGt(wAmnt, actualBalance);
		console.log("w slippage", (10000 * (wAmnt - actualBalance)) / wAmnt);
	}

	// function testDeploymentHarvest() public {
	// SCYVault dStrat = SCYVault(payable(0x8DA9CD7232611Fef7b1f05Ab80ea9bB977F52A79));
	// address u = 0xf09c27934A92c56c7C0dD6cBAc858C35fBd5170f;
	// uint256 shares = dStrat.balanceOf(u);
	// uint256 tvl = dStrat.getAndUpdateTvl();
	// uint256 amount = dStrat.sharesToUnderlying(shares);
	// uint256 uBal = dStrat.underlyingBalance(u);
	// console.log("shares, tvl, amount", shares, tvl, amount);
	// console.log("uBal", uBal, amount);
	// 	vm.startPrank(0x6DdF9DA4C37DF97CB2458F85050E09994Cbb9C2A);
	// 	HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
	// 	params1[0] = harvestParams;
	// 	params1[0].min = 0;
	// 	params1[0].deadline = block.timestamp + 1;
	// 	HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);
	// 	uint256 tvl = dStrat.getAndUpdateTvl();
	// 	(uint256[] memory harvestAmnts, ) = dStrat.harvest(dStrat.getTvl(), 0, params1, params2);
	// 	vm.stopPrank();
	// 	assertGt(harvestAmnts[0], 0);
	// }
}
