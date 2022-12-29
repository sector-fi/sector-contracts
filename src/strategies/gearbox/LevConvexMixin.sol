// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import { ICreditFacade, ICreditManagerV2, MultiCall } from "../../interfaces/gearbox/ICreditFacade.sol";
// import { IPriceOracleV2 } from "../../interfaces/gearbox/IPriceOracleV2.sol";
// import { StratAuth } from "../../common/StratAuth.sol";
// import { Auth, AuthConfig } from "../../common/Auth.sol";
// import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
// import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// import { ICurvePool } from "../../interfaces/curve/ICurvePool.sol";
// import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
// import { ICurveV1Adapter } from "../../interfaces/gearbox/adapters/ICurveV1Adapter.sol";
// import { IBaseRewardPool } from "../../interfaces/gearbox/adapters/IBaseRewardPool.sol";
// import { IBooster } from "../../interfaces/gearbox/adapters/IBooster.sol";
// import { EAction, HarvestSwapParams } from "../../interfaces/Structs.sol";
// import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";
// import { BytesLib } from "../../libraries/BytesLib.sol";

// // import "hardhat/console.sol";

// struct LevConvexConfig {
// 	address curveAdapter;
// 	address convexRewardPool;
// 	address creditFacade;
// 	uint16 coinId;
// 	address underlying;
// 	uint16 leverageFactor;
// 	address convexBooster;
// 	address farmRouter;
// }

// abstract conract ILevConvex {
// 	using SafeERC20 for IERC20;

// 	// USDC
// 	ICreditFacade public creditFacade;

// 	ICreditManagerV2 public creditManager;

// 	IPriceOracleV2 public priceOracle = IPriceOracleV2(0x6385892aCB085eaa24b745a712C9e682d80FF681);

// 	ISwapRouter public uniswapV3Adapter;

// 	ICurveV1Adapter public curveAdapter;
// 	ICurveV1Adapter public threePoolAdapter =
// 		ICurveV1Adapter(0xbd871de345b2408f48C1B249a1dac7E0D7D4F8f9);
// 	IBaseRewardPool public convexRewardPool;
// 	IBooster public convexBooster;
// 	ISwapRouter public farmRouter;

// 	IERC20 public farmToken;
// 	IERC20 public immutable underlying;

// 	uint16 convexPid;
// 	// leverage factor is how much we borrow in %
// 	// ex 2x leverage = 100, 3x leverage = 200
// 	uint16 public leverageFactor;
// 	uint256 immutable dec;
// 	uint256 constant shortDec = 1e18;
// 	address public credAcc; // gearbox credit account // TODO can it expire?
// 	uint16 coinId;
// 	bool threePool = true;


// 	//// INTERNAL METHODS

// 	function _increasePosition(uint256 borrowAmnt, uint256 totalAmount) internal virtual;

// 	function _decreasePosition(uint256 lpAmount) internal virtual;

// 	function _closePosition() internal virtual;

// 	function _openAccount(uint256 amount) internal virtual;

// 	// this is actually not totally accurate
// 	function collateralToUnderlying() public view returns (uint256) {
// 		uint256 amountOut = curveAdapter.calc_withdraw_one_coin(1e18, int128(uint128(coinId)));
// 		uint256 currentLeverage = getLeverage();
// 		if (currentLeverage == 0) return (100 * amountOut) / (leverageFactor + 100);
// 		return (100 * amountOut) / currentLeverage;
// 	}

// 	function collateralBalance() public view returns (uint256) {
// 		if (credAcc == address(0)) return 0;
// 		return convexRewardPool.balanceOf(credAcc);
// 	}

// 	/// @dev gearbox accounting is overly concervative so we use calc_withdraw_one_coin
// 	/// to compute totalAsssets
// 	function getTotalTVL() public view returns (uint256) {
// 		if (credAcc == address(0)) return 0;
// 		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
// 		uint256 totalAssets = getTotalAssets();
// 		return totalAssets > totalOwed ? totalAssets - totalOwed : 0;
// 	}

// 	function getTotalAssets() public view returns (uint256 totalAssets) {
// 		totalAssets = curveAdapter.calc_withdraw_one_coin(
// 			convexRewardPool.balanceOf(credAcc),
// 			int128(uint128(coinId))
// 		);
// 	}

// 	function getAndUpdateTVL() public view returns (uint256) {
// 		return getTotalTVL();
// 	}

// 	event AdjustLeverage(uint256 newLeverage);
// 	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);
// 	event Deposit(address sender, uint256 amount);
// 	event Redeem(address sender, uint256 amount);

// 	error WrongVaultUnderlying();
// }
