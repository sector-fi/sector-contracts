// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { HLPConfig, HarvestSwapParams, NativeToken } from "interfaces/Structs.sol";
import { HLPCore } from "strategies/hlp/HLPCore.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { SCYStratUtils } from "../common/SCYStratUtils.sol";
import { UniswapMixin } from "../common/UniswapMixin.sol";

import { SCYVault, AuthConfig, FeeConfig, Auth } from "vaults/ERC5115/SCYVault.sol";
import { SCYVaultConfig } from "interfaces/ERC5115/ISCYVault.sol";
import { ISCYVault } from "interfaces/ERC5115/ISCYVault.sol";

import { MasterChefCompMulti } from "strategies/hlp/MasterChefCompMulti.sol";
import { SolidlyAave } from "strategies/hlp/SolidlyAave.sol";
import { CamelotAave } from "strategies/hlp/CamelotAave.sol";
import { sectGrail } from "strategies/modules/camelot/sectGrail.sol";
import { MiniChefAave } from "strategies/hlp/MiniChefAave.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { INFTPool } from "strategies/modules/camelot/CamelotFarm.sol";

import "forge-std/StdJson.sol";

import "hardhat/console.sol";

contract HLPSetup is SCYStratUtils, UniswapMixin {
	using stdJson for string;

	// string TEST_STRATEGY = "HLP_USDC-MOVR_Solar-Well_moonriver";
	// string TEST_STRATEGY = "HLP_USDC-ETH_Velo-Aave_optimism";
	string TEST_STRATEGY = "HLP_USDC-ETH_Xcal-Aave_arbitrum";
	// string TEST_STRATEGY = "HLP_USDC-ETH_Camelot-Aave_arbitrum";
	// string TEST_STRATEGY = "HLP_USDC-ETH_Sushi-Aave_arbitrum";

	address xGrail = 0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b;

	string lenderType;
	uint256 currentFork;

	HLPCore strategy;

	SCYVaultConfig vaultConfig;
	HLPConfig config;
	string contractType;

	struct HLPConfigJSON {
		address a_underlying;
		address b_short;
		address c_uniPair;
		address d1_cTokenLend;
		address d2_cTokenBorrow;
		address e1_farmToken;
		uint256 e2_farmId;
		address e3_uniFarm;
		address f_farmRouter;
		address[] h_harvestPath;
		address l1_comptroller;
		address l2_lendRewardToken;
		address[] l3_lendRewardPath;
		address l4_lendRewardRouter;
		string l5_lenderType;
		uint256 n_nativeToken;
		string o_contract;
		string x_chain;
	}

	function getStrategy() public view virtual returns (string memory) {
		return TEST_STRATEGY;
	}

	function setupHook() public virtual {}

	// TODO we can return a full array for a given chain
	// and test all strats...
	function getConfig(string memory symbol) public returns (HLPConfig memory _config) {
		string memory root = vm.projectRoot();
		string memory path = string.concat(root, "/ts/config/strategies.json");
		string memory json = vm.readFile(path);
		// bytes memory names = json.parseRaw(".strats");
		// string[] memory strats = abi.decode(names, (string[]));
		bytes memory strat = json.parseRaw(string.concat(".", symbol));
		HLPConfigJSON memory stratJson = abi.decode(strat, (HLPConfigJSON));

		_config.underlying = stratJson.a_underlying;
		_config.short = stratJson.b_short;
		_config.uniPair = stratJson.c_uniPair;
		_config.cTokenLend = stratJson.d1_cTokenLend; // collateral token
		_config.cTokenBorrow = stratJson.d2_cTokenBorrow; // collateral token
		_config.farmToken = stratJson.e1_farmToken;
		_config.farmId = stratJson.e2_farmId;
		_config.uniFarm = stratJson.e3_uniFarm;
		_config.farmRouter = stratJson.f_farmRouter;
		_config.comptroller = stratJson.l1_comptroller;
		_config.lendRewardToken = stratJson.l2_lendRewardToken;
		_config.lendRewardRouter = stratJson.l4_lendRewardRouter;
		_config.nativeToken = NativeToken(stratJson.n_nativeToken);

		harvestParams.path = stratJson.h_harvestPath;
		harvestLendParams.path = stratJson.l3_lendRewardPath;
		contractType = stratJson.o_contract;
		lenderType = stratJson.l5_lenderType;

		string memory RPC_URL = vm.envString(string.concat(stratJson.x_chain, "_RPC_URL"));
		uint256 BLOCK = vm.envUint(string.concat(stratJson.x_chain, "_BLOCK"));

		currentFork = vm.createFork(RPC_URL, BLOCK);
		vm.selectFork(currentFork);
	}

	function setUp() public {
		config = getConfig(getStrategy());

		// TODO use JSON
		underlying = IERC20(config.underlying);

		/// todo should be able to do this via address and mixin
		vaultConfig.symbol = "TST";
		vaultConfig.name = "TEST";
		vaultConfig.yieldToken = config.uniPair;
		vaultConfig.underlying = IERC20(config.underlying);
		vaultConfig.maxTvl = type(uint128).max;

		vault = deploySCYVault(
			AuthConfig(owner, guardian, manager),
			FeeConfig(treasury, .1e18, 0),
			vaultConfig
		);

		mLp = vault.MIN_LIQUIDITY();
		config.vault = address(vault);

		AuthConfig memory authConfig = AuthConfig(owner, guardian, manager);

		if (compare(contractType, "MasterChefCompMulti"))
			strategy = new MasterChefCompMulti(authConfig, config);
		if (compare(contractType, "SolidlyAave")) strategy = new SolidlyAave(authConfig, config);
		if (compare(contractType, "CamelotAave")) {
			vm.expectRevert("SectGrail address must be passed in");
			new CamelotAave(authConfig, config);

			sectGrail sGrailLogic = new sectGrail();
			sectGrail sGrail = sectGrail(
				address(
					new ERC1967Proxy(
						address(sGrailLogic),
						abi.encodeWithSelector(sectGrail.initialize.selector, xGrail)
					)
				)
			);
			// we pass sGrail as the uniPair and pull uniPair out of farm params
			address lpToken = config.uniPair;
			config.uniPair = address(sGrail);
			strategy = new CamelotAave(authConfig, config);

			// whitelist farm and yieldBooster
			sGrail.updateWhitelist(config.uniFarm, true);

			// tests use this
			config.uniPair = lpToken;
		}
		if (compare(contractType, "MiniChefAave")) strategy = new MiniChefAave(authConfig, config);

		vault.initStrategy(address(strategy));
		underlying.approve(address(vault), type(uint256).max);

		configureUtils(config.underlying, address(strategy));
		configureUniswapMixin(config.uniPair, config.short);
		// deposit(mLp);
		setupHook();
	}

	function rebalance() public override {
		uint256 priceOffset = strategy.getPriceOffset();
		strategy.rebalance(priceOffset);
		assertApproxEqAbs(strategy.getPositionOffset(), 0, 2, "position offset after rebalance");
		skip(1);
	}

	function harvest() public override {
		harvest(vault);
	}

	function harvest(ISCYVault _vault) public {
		HLPCore _strategy = HLPCore(payable(address(_vault.strategy())));
		address owner = Auth(address(_vault)).owner();
		if (!_strategy.harvestIsEnabled()) return;
		vm.warp(block.timestamp + 1 * 60 * 60 * 24);
		harvestParams.min = 0;
		harvestParams.deadline = block.timestamp + 1;

		harvestLendParams.min = 0;
		harvestLendParams.deadline = block.timestamp + 1;

		_strategy.getAndUpdateTvl();
		uint256 tvl = _strategy.getTotalTVL();

		HarvestSwapParams[] memory farmParams = new HarvestSwapParams[](1);
		farmParams[0] = harvestParams;

		HarvestSwapParams[] memory lendParams = new HarvestSwapParams[](1);
		lendParams[0] = harvestLendParams;

		uint256 vaultTvl = _vault.getTvl();

		vm.prank(owner);
		(uint256[] memory harvestAmnts, uint256[] memory harvestLendAmnts) = _vault.harvest(
			vaultTvl,
			vaultTvl / 10,
			farmParams,
			lendParams
		);

		uint256 newTvl = _strategy.getTotalTVL();
		// assertGt(harvestAmnts[0], 0);
		// if (!compare(lenderType, "aave")) assertGt(harvestLendAmnts[0], 0);
		assertGt(newTvl, tvl);
	}

	function noRebalance() public override {
		uint256 priceOffset = strategy.getPriceOffset();
		vm.expectRevert(HLPCore.RebalanceThreshold.selector);
		vm.prank(manager);
		strategy.rebalance(priceOffset);
	}

	function adjustPrice(uint256 fraction) public override {
		moveUniswapPrice(config.uniPair, config.underlying, config.short, fraction);
		adjustOraclePrice(fraction);
	}

	function adjustOraclePrice(uint256 fraction) public {
		if (compare(lenderType, "compound")) adjustCompoundOraclePrice(fraction, address(strategy));
		if (compare(lenderType, "aave")) adjustAaveOraclePrice(fraction, address(strategy));
	}

	function compare(string memory str1, string memory str2) public pure returns (bool) {
		return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
	}
}
