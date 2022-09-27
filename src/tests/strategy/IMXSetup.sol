// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { IMXUtils, UniUtils, IUniswapV2Pair } from "../utils/IMXUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { IMXVault, Strategy } from "../../vaults/IMXVault.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "hardhat/console.sol";

contract IMXSetup is SectorTest, IMXUtils, ERC1155Holder {
	using UniUtils for IUniswapV2Pair;

	uint256 BASIS = 10000;
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	IMXVault vault;
	IMX strategy;

	IMXConfig config;
	HarvestSwapParms harvestParams;

	address manager = address(101);
	address guardian = address(102);
	address treasury = address(103);
	address owner = address(this);

	Strategy strategyConfig;

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		// TODO use JSON
		config.underlying = address(usdc);
		config.short = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
		config.uniPair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1;
		config.poolToken = 0xEE2A27B7c3165A5E2a3FEB113A77B26b46dB0baE; // collateral token
		config.farmToken = 0xeA6887e4a9CdA1B77E70129E5Fba830CdB5cdDef;
		config.farmRouter = 0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106;
		config.maxTvl = type(uint128).max;
		config.owner = owner;
		config.manager = manager;
		config.guardian = guardian;

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = bytes32(bytes("Test Strategy"));
		strategyConfig.yieldToken = config.poolToken;
		strategyConfig.underlying = IERC20(config.underlying);
		strategyConfig.maxTvl = uint128(config.maxTvl);
		strategyConfig.maxDust = 1e18;
		strategyConfig.treasury = treasury;
		strategyConfig.performanceFee = .1e18;

		vault = new IMXVault(owner, guardian, manager, strategyConfig);

		config.vault = address(vault);

		strategy = new IMX();
		strategy.initialize(config);

		vault.initStrategy(address(strategy));
		usdc.approve(address(vault), type(uint256).max);
	}

	function deposit(uint256 amount) public {
		uint256 startTvl = strategy.getTotalTVL();
		deal(address(usdc), address(this), amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		vault.deposit(address(this), address(usdc), amount, (minSharesOut * 9990) / 10000);
		uint256 tvl = strategy.getTotalTVL();
		assertApproxEqAbs(tvl, startTvl + amount, 10, "tvl should be update");
		assertEq(vault.underlyingBalance(address(this)), tvl, "underlying balance");
	}

	function withdraw(uint256 fraction) public {
		uint256 sharesToWithdraw = (vault.balanceOf(address(this)) * fraction) / 1e18;
		uint256 minUnderlyingOut = vault.sharesToUnderlying(sharesToWithdraw);
		vault.redeem(
			address(this),
			sharesToWithdraw,
			address(usdc),
			(minUnderlyingOut * 9990) / 10000
		);
	}

	function adjustPrice(uint256 fraction) public {
		address oracle = ICollateral(config.poolToken).simpleUniswapOracle();
		address stakedToken = ICollateral(config.poolToken).underlying();
		movePrice(config.uniPair, stakedToken, config.underlying, config.short, oracle, fraction);
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
		returns (uint256 expectedPrice, uint256 maxDelta)
	{
		expectedPrice = strategy.getExpectedPrice();
		maxDelta = (expectedPrice * slippage) / BASIS;
	}
}
