// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { IMXUtils, UniUtils, IUniswapV2Pair } from "../utils/IMXUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { IMXVault, Strategy, AuthConfig, FeeConfig } from "../../vaults/IMXVault.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract IMXSetup is SectorTest, IMXUtils {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	// string TEST_STRATEGY = "USDCimxAVAX";
	string TEST_STRATEGY = "USDC-OP-tarot-velo";

	uint256 BASIS = 10000;
	uint256 currentFork;
	uint256 minLp;

	IMXVault vault;
	IMX strategy;

	HarvestSwapParms harvestParams;

	Strategy strategyConfig;

	IERC20 underlying;
	IMXConfig config;

	struct IMXConfigJSON {
		address a_underlying;
		address b_short;
		address c_uniPair;
		address d_poolToken;
		address e_farmToken;
		address f_farmRouter;
		string g_chain;
		address[] h_harvestPath;
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

		string memory RPC_URL = vm.envString(string.concat(stratJson.g_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.g_chain, "_BLOCK"));

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

		vault = new IMXVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, .1e18, 0),
			strategyConfig
		);

		minLp = vault.MIN_LIQUIDITY();
		config.vault = address(vault);

		strategy = new IMX();
		strategy.initialize(config);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);
	}

	function deposit(uint256 amount) public {
		deposit(amount, address(this));
	}

	function deposit(uint256 amount, address acc) public {
		// uint256 startTvl = strategy.getTotalTVL();
		uint256 startTvl = strategy.getAndUpdateTVL();
		uint256 startAccBalance = vault.underlyingBalance(acc);
		deal(address(underlying), acc, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		underlying.approve(address(vault), amount);
		vault.deposit(acc, address(underlying), amount, (minSharesOut * 9930) / 10000);
		uint256 tvl = strategy.getTotalTVL();
		uint256 endAccBalance = vault.underlyingBalance(acc);
		assertApproxEqAbs(tvl, startTvl + amount, (amount * 3) / 1000, "tvl should update");
		assertApproxEqAbs(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			(amount * 3) / 1000,
			"underlying balance"
		);
		assertEq(underlying.balanceOf(address(strategy)), 0);
	}

	function withdraw(uint256 fraction) public {
		uint256 sharesToWithdraw = (vault.balanceOf(address(this)) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(
			address(this),
			sharesToWithdraw,
			address(underlying),
			(minUnderlyingOut * 9990) / 10000
		);
	}

	function adjustPrice(uint256 fraction) public {
		address oracle;
		try ICollateral(config.poolToken).simpleUniswapOracle() returns (address _oracle) {
			oracle = _oracle;
		} catch {
			oracle = ICollateral(config.poolToken).tarotPriceOracle();
		}
		address stakedToken = ICollateral(config.poolToken).underlying();
		movePrice(config.uniPair, stakedToken, config.underlying, config.short, oracle, fraction);
	}

	// function getOracle() public returns (address oracle) {
	// 	try ICollateral(config.poolToken).simpleUniswapOracle() returns (address _oracle) {
	// 		oracle = _oracle;
	// 	}
	// 	catch {
	// 		oracle = ICollateral(config.poolToken).tarotPriceOracle();
	// 	}
	// }

	function moveUniPrice(uint256 fraction) public {
		IUniswapV2Pair pair = IUniswapV2Pair(config.uniPair);
		moveUniswapPrice(pair, config.underlying, config.short, fraction);
	}

	function rebalance() public {
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
