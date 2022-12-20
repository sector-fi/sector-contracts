// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "interfaces/uniswap/ISimpleUniswapOracle.sol";
import { PriceUtils, UniUtils, IUniswapV2Pair } from "../../utils/PriceUtils.sol";

import { HarvestSwapParams } from "interfaces/Structs.sol";
import { SCYWEpochVault, levConvexVault, Strategy, AuthConfig, FeeConfig } from "vaults/strategyVaults/levConvexVault.sol";
import { levConvex } from "strategies/gearbox/levConvex.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SCYStratUtils } from "../common/SCYStratUtils.sol";
import { IDegenNFT } from "interfaces/gearbox/IDegenNFT.sol";
import { ICreditFacade } from "interfaces/gearbox/ICreditFacade.sol";
import { LevConvexConfig } from "strategies/gearbox/levConvex.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract levConvexSetup is SCYStratUtils {
	using UniUtils for IUniswapV2Pair;
	using stdJson for string;

	string RPC_URL = vm.envString("ETH_RPC_URL");
	uint256 BLOCK = vm.envUint("ETH_BLOCK");

	levConvex strategy;

	Strategy strategyConfig;

	address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
	uint16 LEV_FACTOR = 500;

	function setUp() public {
		uint256 fork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(fork);

		// TODO use JSON
		underlying = IERC20(USDC);

		LevConvexConfig memory config = LevConvexConfig({ // deposits adapter - do we need a different one?
			curveAdapter: 0xbfB212e5D9F880bf93c47F3C32f6203fa4845222,
			convexRewardPool: 0xbEf6108D1F6B85c4c9AA3975e15904Bb3DFcA980,
			creditFacade: 0x61fbb350e39cc7bF22C01A469cf03085774184aa,
			coinId: 1, // curve token index
			underlying: USDC,
			leverageFactor: LEV_FACTOR,
			convexBooster: 0xB548DaCb7e5d61BF47A026903904680564855B4E
		});

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.yieldToken = config.convexRewardPool;
		strategyConfig.underlying = IERC20(USDC);

		uint256 maxTvl = 20e6;
		strategyConfig.maxTvl = uint128(maxTvl);

		AuthConfig memory authConfig = AuthConfig({
			owner: owner,
			manager: manager,
			guardian: guardian
		});

		vault = SCYWEpochVault(
			new levConvexVault(authConfig, FeeConfig(treasury, .1e18, 0), strategyConfig)
		);

		mLp = vault.MIN_LIQUIDITY();

		strategy = new levConvex(authConfig, config);

		vault.initStrategy(address(strategy));
		strategy.setVault(address(vault));

		underlying.approve(address(vault), type(uint256).max);

		configureUtils(USDC, address(strategy));

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
		return 50000e6;
	}

	function deposit(address user, uint256 amount) public virtual override {
		uint256 startTvl = vault.getAndUpdateTvl();
		uint256 startAccBalance = vault.underlyingBalance(user);
		deal(address(underlying), user, amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);

		vm.startPrank(user);
		underlying.approve(address(vault), amount);
		vault.deposit(user, address(underlying), amount, (minSharesOut * 9930) / 10000);
		vm.stopPrank();

		uint256 tvl = vault.getAndUpdateTvl();
		uint256 endAccBalance = vault.underlyingBalance(user);

		// TODO this implies a 1.4% slippage / deposit fee
		assertApproxEqRel(tvl, startTvl + amount, .015e18, "tvl should update");
		assertApproxEqRel(
			tvl - startTvl,
			endAccBalance - startAccBalance,
			.01e18,
			"underlying balance"
		);
		assertEq(vault.getFloatingAmount(address(underlying)), 0);

		// this is necessary for stETH strategy (so closing account doesn't happen in same block)
		vm.roll(block.number + 1);
	}
}
