// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../utils/PriceUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { SCYVault, IMXVault, Strategy, AuthConfig, FeeConfig } from "../../vaults/IMXVault.sol";
import { IMX, IMXCore } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StratUtils } from "./StratUtils.sol";
import { IntegrationTest } from "./Integration.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract SetupImx is SectorTest, StratUtils, IntegrationTest {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	// string TEST_STRATEGY = "USDCimxAVAX";
	string TEST_STRATEGY = "USDC-OP-tarot-velo";

	uint256 currentFork;

	IMX strategy;

	Strategy strategyConfig;
	IMXConfig config;

	struct IMXConfigJSON {
		address a_underlying;
		address b_short;
		address c_uniPair;
		address d_poolToken;
		address e_farmToken;
		address f_farmRouter;
		address[] h_harvestPath;
		string x_chain;
	}

	// TODO we can return a full array for a given chain
	// and test all strats...
	function getConfig(string memory symbol) public returns (IMXConfig memory _config) {
		string memory root = vm.projectRoot();
		string memory path = string.concat(root, "/ts/config/strategies.json");
		string memory json = vm.readFile(path);
		// bytes memory names = json.parseRaw(".strats");
		// string[] memory strats = abi.decode(names, (string[]));
		bytes memory strat = json.parseRaw(string.concat(".", symbol));
		IMXConfigJSON memory stratJson = abi.decode(strat, (IMXConfigJSON));

		_config.underlying = stratJson.a_underlying;
		_config.short = stratJson.b_short;
		_config.uniPair = stratJson.c_uniPair;
		_config.poolToken = stratJson.d_poolToken; // collateral token
		_config.farmToken = stratJson.e_farmToken;
		_config.farmRouter = stratJson.f_farmRouter;
		_config.maxTvl = type(uint128).max;
		_config.owner = owner;
		_config.manager = manager;
		_config.guardian = guardian;

		harvestParams.path = stratJson.h_harvestPath;

		string memory RPC_URL = vm.envString(string.concat(stratJson.x_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.x_chain, "_BLOCK"));

		currentFork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(currentFork);
	}

	function setUp() public {
		config = getConfig(TEST_STRATEGY);

		// TODO use JSON
		underlying = IERC20(config.underlying);

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = config.poolToken;
		strategyConfig.underlying = IERC20(config.underlying);
		strategyConfig.maxTvl = uint128(config.maxTvl);

		vault = SCYVault(
			new IMXVault(
				AuthConfig(owner, guardian, manager),
				FeeConfig(treasury, .1e18, 0),
				strategyConfig
			)
		);

		mLp = vault.MIN_LIQUIDITY();
		config.vault = address(vault);

		strategy = new IMX();
		strategy.initialize(config);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);

		configureUtils(config.underlying, config.short, config.uniPair, address(strategy));

		// deposit(mLp);
	}

	function noRebalance() public override {
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		vm.expectRevert(IMXCore.RebalanceThreshold.selector);
		strategy.rebalance(expectedPrice, maxDelta);
	}

	function adjustPrice(uint256 fraction) public override {
		address oracle;
		try ICollateral(config.poolToken).simpleUniswapOracle() returns (address _oracle) {
			oracle = _oracle;
		} catch {
			oracle = ICollateral(config.poolToken).tarotPriceOracle();
		}
		address stakedToken = ICollateral(config.poolToken).underlying();
		moveImxPrice(
			config.uniPair,
			stakedToken,
			config.underlying,
			config.short,
			oracle,
			fraction
		);
	}

	function harvest() public override {
		if (!strategy.harvestIsEnabled()) return;
		vm.warp(block.timestamp + 1 * 60 * 60 * 24);
		harvestParams.min = 0;
		harvestParams.deadline = block.timestamp + 1;
		strategy.getAndUpdateTVL();
		uint256 tvl = strategy.getTotalTVL();
		uint256 harvestAmnt = strategy.harvest(harvestParams);
		uint256 newTvl = strategy.getTotalTVL();
		assertGt(harvestAmnt, 0);
		assertGt(newTvl, tvl);
	}

	function rebalance() public override {
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		assertGt(strategy.getPositionOffset(), strategy.rebalanceThreshold());
		strategy.rebalance(expectedPrice, maxDelta);
		assertApproxEqAbs(strategy.getPositionOffset(), 0, 2, "position offset after rebalance");
	}

	// slippage in basis points
	function getSlippageParams(uint256 slippage)
		public
		view
		returns (uint256 expectedPrice, uint256 maxDelta)
	{
		expectedPrice = strategy.getExpectedPrice();
		maxDelta = (expectedPrice * slippage) / BASIS;
	}
}
