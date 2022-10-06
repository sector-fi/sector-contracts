// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICollateral } from "../../interfaces/imx/IImpermax.sol";
import { ISimpleUniswapOracle } from "../../interfaces/uniswap/ISimpleUniswapOracle.sol";
import { IMXUtils, UniUtils, IUniswapV2Pair } from "../utils/IMXUtils.sol";

import { SectorTest } from "../utils/SectorTest.sol";
import { IMXConfig, HarvestSwapParms } from "../../interfaces/Structs.sol";
import { IMXLend, Strategy } from "../../vaults/IMXLend.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

// import "hardhat/console.sol";

contract IMXLending is SectorTest, IMXUtils, ERC1155Holder {
	using UniUtils for IUniswapV2Pair;

	uint256 BASIS = 10000;
	string AVAX_RPC_URL = vm.envString("AVAX_RPC_URL");
	uint256 AVAX_BLOCK = vm.envUint("AVAX_BLOCK");
	uint256 avaxFork;

	IMXLend vault;

	HarvestSwapParms harvestParams;

	Strategy strategyConfig;

	IERC20 usdc = IERC20(0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664);
	IERC20 avax = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
	IERC20 underlying;

	address strategy = 0x3b611a8E02908607c409b382D5671e8b3e39755d;
	address strategyEth = 0xBE48d2910a8908d33A1fE11d4F156eEf87ED563c;
	uint256 minLp;

	function setUp() public {
		avaxFork = vm.createFork(AVAX_RPC_URL, AVAX_BLOCK);
		vm.selectFork(avaxFork);

		/// todo should be able to do this via address and mixin
		strategyConfig.symbol = "TST";
		strategyConfig.name = "TEST";
		strategyConfig.addr = strategy;
		strategyConfig.yieldToken = strategy;
		strategyConfig.underlying = IERC20(address(usdc));
		strategyConfig.maxTvl = type(uint128).max;
		strategyConfig.treasury = treasury;
		strategyConfig.performanceFee = .1e18;

		underlying = IERC20(address(strategyConfig.underlying));

		vault = new IMXLend(owner, guardian, manager, strategyConfig);
		minLp = vault.MIN_LIQUIDITY();
		usdc.approve(address(vault), type(uint256).max);
	}

	function testDeposit() public {
		deposit(1000e6);
	}

	function testWithdraw() public {
		deposit(1000e6);
		withdrawCheck(.4e18);
	}

	function testManagerWithdraw() public {
		uint256 amnt = 1000e6;
		deposit(1000e6);
		vault.closePosition(0);
		uint256 floatBalance = vault.uBalance();
		assertApproxEqAbs(floatBalance, amnt, 10);
		assertEq(underlying.balanceOf(address(vault)), floatBalance);
		vm.roll(block.number + 1);
		vault.depositIntoStrategy(floatBalance, 0);
	}

	function deposit(uint256 amount) public {
		uint256 startTvl = vault.getStrategyTvl();
		deal(address(usdc), address(this), amount);
		uint256 minSharesOut = vault.underlyingToShares(amount);
		vault.deposit(address(this), address(usdc), amount, (minSharesOut * 9990) / 10000);
		uint256 tvl = vault.getStrategyTvl();
		assertApproxEqAbs(tvl, startTvl + amount, 10, "tvl should be correct");
		uint256 vaultBalance = IERC20(vault.yieldToken()).balanceOf(address(vault));
		assertEq(
			vault.balanceOf(address(this)),
			vaultBalance - minLp,
			"vault balance should match user"
		);
		uint256 lockedBalance = vault.underlyingBalance(address(1));
		assertApproxEqAbs(
			vault.underlyingBalance(address(this)) + lockedBalance,
			tvl,
			minLp,
			"underlying balance should match tvl"
		);
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

	function withdrawCheck(uint256 fraction) public {
		uint256 startTvl = vault.getStrategyTvl();
		withdraw(fraction);

		uint256 tvl = vault.getStrategyTvl();
		uint256 lockedBalance = vault.underlyingBalance(address(1));

		assertApproxEqAbs(tvl, (startTvl * (1e18 - fraction)) / 1e18, minLp);
		assertApproxEqAbs(vault.underlyingBalance(address(this)) + lockedBalance, tvl, 10);
	}
}
