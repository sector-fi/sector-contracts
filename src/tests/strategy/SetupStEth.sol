// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../utils/PriceUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { SCYVault, stETHVault, Strategy, AuthConfig, FeeConfig } from "vaults/strategyVaults/stETHVault.sol";
import { stETH as stETHStrategy } from "../../strategies/gearbox/stETH.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { StratUtils } from "./StratUtils.sol";
import { IDegenNFT } from "interfaces/gearbox/IDegenNFT.sol";
import { ICreditFacade } from "interfaces/gearbox/ICreditFacade.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract SetupStEth is SectorTest, StratUtils {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	string RPC_URL = vm.envString("ETH_RPC_URL");
	uint256 BLOCK = vm.envUint("ETH_BLOCK");

	stETHStrategy strategy;

	Strategy strategyConfig;

	address stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
	address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

	function setUp() public {
		uint256 fork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(fork);

		// TODO use JSON
		underlying = IERC20(USDC);

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = stETH;
		strategyConfig.underlying = IERC20(USDC);

		uint256 maxTvl = 20e6;
		strategyConfig.maxTvl = uint128(maxTvl);

		AuthConfig memory authConfig = AuthConfig({
			owner: owner,
			manager: manager,
			guardian: guardian
		});

		vault = SCYVault(new stETHVault(authConfig, FeeConfig(treasury, .1e18, 0), strategyConfig));

		mLp = vault.MIN_LIQUIDITY();

		uint16 targetLeverage = 500;
		strategy = new stETHStrategy(authConfig, USDC, targetLeverage);

		vault.initStrategy(address(strategy));
		strategy.setVault(address(vault));

		underlying.approve(address(vault), type(uint256).max);

		configureUtils(USDC, address(0), address(0), address(strategy));

		/// mint dege nft to strategy
		ICreditFacade creditFacade = strategy.creditFacade();

		IDegenNFT degenNFT = IDegenNFT(creditFacade.degenNFT());
		address minter = degenNFT.minter();

		vm.prank(minter);
		degenNFT.mint(address(strategy), 100);

		// so close account doesn't create issues
		vm.roll(1);
		// deposit(mLp);
	}

	function noRebalance() public override {}

	function adjustPrice(uint256 fraction) public override {}

	function harvest() public override {}

	function rebalance() public override {}

	// slippage in basis points
	function getSlippageParams(uint256 slippage)
		public
		view
		returns (uint256 expectedPrice, uint256 maxDelta)
	{
		// expectedPrice = strategy.getExpectedPrice();
		// maxDelta = (expectedPrice * slippage) / BASIS;
	}

	function adjustOraclePrice(uint256 fraction) public {}

	function getAmnt() public view virtual override returns (uint256) {
		/// needs to be over Gearbox deposit min
		return 100000e6;
	}
}
