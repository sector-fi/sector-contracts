// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
// import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
// import { PriceUtils, UniUtils, IUniswapV2Pair } from "../utils/PriceUtils.sol";

// import { SectorTest } from "../utils/SectorTest.sol";
// import { IMXConfig, HarvestSwapParams } from "../../interfaces/Structs.sol";
// import { SCYVault, IMXVault, Strategy, AuthConfig, FeeConfig } from "vaults/strategyVaults/IMXVault.sol";
// import { IMX, IMXCore } from "../../strategies/imx/IMX.sol";
// import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import { StratUtils } from "./StratUtils.sol";

// import "forge-std/StdJson.sol";

// import "hardhat/console.sol";

// contract SetupStEth is SectorTest, StratUtils {
// 	using UniUtils for IUniswapV2Pair;
// 	using stdJson for string;

// 	uint256 currentFork;

// 	IMX strategy;

// 	Strategy strategyConfig;

// 	function setUp() public {
// 		// TODO use JSON
// 		underlying = IERC20(config.underlying);

// 		/// todo should be able to do this via address and mixin
// 		strategyConfig.symbol = "TST";
// 		strategyConfig.name = "TEST";
// 		strategyConfig.yieldToken = config.poolToken;
// 		strategyConfig.underlying = IERC20(config.underlying);
// 		strategyConfig.maxTvl = uint128(config.maxTvl);

// 		AuthConfig memory authConfig = AuthConfig({
// 			owner: owner,
// 			manager: manager,
// 			guardian: guardian
// 		});

// 		vault = SCYVault(new IMXVault(authConfig, FeeConfig(treasury, .1e18, 0), strategyConfig));

// 		mLp = vault.MIN_LIQUIDITY();
// 		config.vault = address(vault);

// 		strategy = new IMX(authConfig, config);

// 		vault.initStrategy(address(strategy));
// 		underlying.approve(address(vault), type(uint256).max);

// 		configureUtils(config.underlying, config.short, config.uniPair, address(strategy));

// 		// deposit(mLp);
// 	}

// 	function noRebalance() public override {
// 		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
// 		vm.expectRevert(IMXCore.RebalanceThreshold.selector);
// 		vm.prank(manager);
// 		strategy.rebalance(expectedPrice, maxDelta);
// 	}

// 	function adjustPrice(uint256 fraction) public override {
// 		address oracle;
// 		try ICollateral(config.poolToken).simpleUniswapOracle() returns (address _oracle) {
// 			oracle = _oracle;
// 		} catch {
// 			oracle = ICollateral(config.poolToken).tarotPriceOracle();
// 		}
// 		address stakedToken = ICollateral(config.poolToken).underlying();
// 		moveImxPrice(
// 			config.uniPair,
// 			stakedToken,
// 			config.underlying,
// 			config.short,
// 			oracle,
// 			fraction
// 		);
// 	}

// 	function harvest() public override {
// 		if (!strategy.harvestIsEnabled()) return;
// 		vm.warp(block.timestamp + 1 * 60 * 60 * 24);

// 		HarvestSwapParams[] memory params1 = new HarvestSwapParams[](1);
// 		params1[0] = harvestParams;
// 		params1[0].min = 0;
// 		params1[0].deadline = block.timestamp + 1;
// 		HarvestSwapParams[] memory params2 = new HarvestSwapParams[](0);

// 		strategy.getAndUpdateTVL();
// 		uint256 tvl = strategy.getTotalTVL();
// 		(uint256[] memory harvestAmnts, ) = vault.harvest(vault.getTvl(), 0, params1, params2);
// 		uint256 newTvl = strategy.getTotalTVL();
// 		assertGt(harvestAmnts[0], 0);
// 		assertGt(newTvl, tvl);
// 	}

// 	function rebalance() public override {
// 		(uint256 expectedPrice, uint256 maxDelta) = getSlippageParams(10); // .1%;
// 		assertGt(strategy.getPositionOffset(), strategy.rebalanceThreshold());
// 		strategy.rebalance(expectedPrice, maxDelta);
// 		assertApproxEqAbs(strategy.getPositionOffset(), 0, 6, "position offset after rebalance");
// 	}

// 	// slippage in basis points
// 	function getSlippageParams(uint256 slippage)
// 		public
// 		view
// 		returns (uint256 expectedPrice, uint256 maxDelta)
// 	{
// 		expectedPrice = strategy.getExpectedPrice();
// 		maxDelta = (expectedPrice * slippage) / BASIS;
// 	}

// 	function adjustOraclePrice(uint256 fraction) public {
// 		// move both
// 		adjustPrice(fraction);
// 		// undo uniswap move
// 		moveUniswapPrice(uniPair, config.underlying, config.short, (1e18 * 1e18) / fraction);
// 	}
// }
