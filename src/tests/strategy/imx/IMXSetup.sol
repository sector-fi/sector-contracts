// SPDX_License_Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../../utils/PriceUtils.sol";

import { SectorTest } from "../../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParams } from "interfaces/Structs.sol";
import { IMX, IMXCore } from "strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SCYStratUtils } from "../common/SCYStratUtils.sol";
import { UniswapMixin } from "../common/UniswapMixin.sol";

import { SCYVault, AuthConfig, FeeConfig } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract IMXSetup is SectorTest, SCYStratUtils, UniswapMixin {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	// avalanche
	// string TEST_STRATEGY = "USDC_IMX_AVAX";

	// optimism
	string TEST_STRATEGY = "LLP_ETH-USDC_Tarot-Velo_optimism";
	// string TEST_STRATEGY = "LLP_USDC-ETH_Tarot-Velo_optimism";
	// string TEST_STRATEGY = "LLP_ETH-USDC-Tarot_Velo";
	// string TEST_STRATEGY = "LLP_USDC-OP-Tarot_Velo";
	// string TEST_STRATEGY = "LLP_USDC-VELO_Tarot_Velo";

	// arbitrum
	// string TEST_STRATEGY = "LLP_USDC-ETH_Tarot-Xcal_arbitrum";
	// string TEST_STRATEGY = "LLP_ETH-USDC_Tarot-Xcal_arbitrum";

	// string TEST_STRATEGY = "LLP_USDC-XCAL_Tarot_Xcal";

	uint256 currentFork;

	IMX strategy;

	SCYVaultConfig vaultConfig;
	IMXConfig config;

	struct IMXConfigJSON {
		address a1_underlying;
		bool a2_acceptsNativeToken;
		address b_short;
		address c0_uniPair;
		address c1_pairRouter;
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

		_config.underlying = stratJson.a1_underlying;
		_config.short = stratJson.b_short;
		_config.uniPair = stratJson.c0_uniPair;
		_config.poolToken = stratJson.d_poolToken; // collateral token
		_config.farmToken = stratJson.e_farmToken;
		_config.farmRouter = stratJson.f_farmRouter;

		harvestParams.path = stratJson.h_harvestPath;
		vaultConfig.acceptsNativeToken = stratJson.a2_acceptsNativeToken;

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
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = config.poolToken;
		vaultConfig.underlying = IERC20(config.underlying);
		vaultConfig.maxTvl = type(uint128).max;

		AuthConfig memory authConfig = AuthConfig({
			owner: owner,
			manager: manager,
			guardian: guardian
		});

		vault = deploySCYVault(authConfig, FeeConfig(treasury, .1e18, 0), vaultConfig);

		mLp = vault.MIN_LIQUIDITY();
		config.vault = address(vault);

		strategy = new IMX(authConfig, config);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);

		configureUtils(config.underlying, address(strategy));
		configureUniswapMixin(config.uniPair, config.short);

		// deposit(mLp);
	}

	function noRebalance() public override {
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		vm.expectRevert(IMXCore.RebalanceThreshold.selector);
		vm.prank(manager);
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
		vm.warp(block.timestamp + 1 * 60 * 60 * 24);

		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
		params1[0] = harvestParams;
		params1[0].min = 0;
		params1[0].deadline = block.timestamp + 1;
		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

		strategy.getAndUpdateTvl();
		uint256 tvl = strategy.getTotalTVL();
		uint256 vaultTvl = vault.getTvl();
		(uint256[] memory harvestAmnts, ) = vault.harvest(
			vaultTvl,
			vaultTvl / 100,
			params1,
			params2
		);
		uint256 newTvl = strategy.getTotalTVL();

		if (!strategy.harvestIsEnabled()) return;
		assertGt(harvestAmnts[0], 0);
		assertGt(newTvl, tvl);
	}

	function rebalance() public override {
		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
		assertGt(strategy.getPositionOffset(), strategy.rebalanceThreshold());
		vm.prank(manager);
		strategy.rebalance(expectedPrice, maxDelta);
		assertApproxEqAbs(strategy.getPositionOffset(), 0, 11, "position offset after rebalance");
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

	function adjustOraclePrice(uint256 fraction) public {
		// move both
		adjustPrice(fraction);
		// undo uniswap move
		moveUniswapPrice(uniPair, config.underlying, config.short, (1e18 * 1e18) / fraction);
	}
}
