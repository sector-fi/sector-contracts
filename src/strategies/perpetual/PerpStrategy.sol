// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity 0.8.16;
// pragma experimental ABIEncoderV2;

// import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// // import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
// import { IVault } from "@perp/curie-contract/contracts/interface/IVault.sol";
// import { IClearingHouse } from "@perp/curie-contract/contracts/interface/IClearingHouse.sol";
// import { IMarketRegistry } from "@perp/curie-contract/contracts/interface/IMarketRegistry.sol";
// import { IAccountBalance } from "@perp/curie-contract/contracts/interface/IAccountBalance.sol";
// import { IBaseToken } from "@perp/curie-contract/contracts/interface/IBaseToken.sol";
// import { IClearingHouseConfig } from "@perp/curie-contract/contracts/interface/IClearingHouseConfig.sol";
// import { IIndexPrice } from "@perp/curie-contract/contracts/interface/IIndexPrice.sol";
// import { IOrderBook } from "@perp/curie-contract/contracts/interface/IOrderBook.sol";
// import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
// import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";

// // import { FullMath } from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

// // as a fungible vault, shares should be calculated based on the actual account value
// // but we can't do this onchain due to the restriction of uniswap v3
// // instead, PERP use index price based account value as reference
// // this may makes shares not 100% accurate when index price != market price, and may have potential flaw
// // in order to mitigate this
// // we suggest to add more restriction to user who deposit/redeem in the same block
// // a few potential solutions:
// //   1. add a cool down period between deposit & withdraw
// //   2. 2 step withdraw
// //   3. remove liquidity and close entire position before calculating shares ( 100% accurate but cost extra fees )
// contract FungibleVault is ReentrancyGuard, ERC20 {
// 	// using SafeMath for uint256;
// 	using FixedPointMathLib for uint256;

// 	// PERP
// 	address public vault;
// 	address public clearingHouse;
// 	address public clearingHouseConfig;
// 	address public marketRegistry;
// 	address public baseToken;

// 	// Uniswap
// 	address public uniswapPool;
// 	int24 internal _minTick;
// 	int24 internal _maxTick;

// 	// TODO impl EIP4626
// 	address public asset;

// 	constructor(
// 		address vaultArg,
// 		address marketRegistryArg,
// 		address baseTokenArg
// 	) ERC20("FungibleVault", "VAT") {
// 		require(IBaseToken(baseTokenArg).isOpen(), "market is closed");
// 		clearingHouse = IVault(vaultArg).getClearingHouse();
// 		require(clearingHouse != address(0), "ClearingHouse not found");

// 		vault = vaultArg;
// 		baseToken = baseTokenArg;
// 		marketRegistry = marketRegistryArg;
// 		clearingHouseConfig = IClearingHouse(clearingHouse).getClearingHouseConfig();
// 		require(clearingHouseConfig != address(0), "ClearingHouseConfig not found");

// 		// full range = mix tick ~ max tick
// 		uniswapPool = IMarketRegistry(marketRegistryArg).getPool(baseTokenArg);
// 		int24 tickSpacing = IUniswapV3Pool(uniswapPool).tickSpacing();
// 		_minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
// 		_maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

// 		// overwrite decimals, make it same as asset
// 		asset = IVault(vaultArg).getSettlementToken();
// 		require(asset != address(0), "Vault's settlement token not found");
// 		uint8 assetDecimals = ERC20(asset).decimals();
// 		require(assetDecimals > 0, "asset decimals is 0");
// 		_setupDecimals(assetDecimals);
// 	}

// 	function deposit(uint256 amount, address receiver) external nonReentrant returns (uint256) {
// 		require(amount > 0, "deposit 0");
// 		require(receiver != address(0), "receiver is 0");

// 		// TODO rebalance to ?x leverage

// 		// deposit to perp
// 		SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amount);
// 		IVault(vault).deposit(address(asset), amount);

// 		// opens a full range order
// 		// convert amount to 18 decimals
// 		uint256 amount_18 = _convertTokenDecimals(amount, decimals(), 18);
// 		// quote (usd) = amount / 2
// 		uint256 quote = amount_18 / 2;
// 		// base (position) = (amount - quote) / base TWAP
// 		uint32 twapInterval = IClearingHouseConfig(clearingHouseConfig).getTwapInterval();
// 		uint256 baseTwap = IIndexPrice(baseToken).getIndexPrice(twapInterval);
// 		uint256 base = (amount_18 - quote).mulDivDown(1e18, baseTwap);

// 		IClearingHouse.AddLiquidityResponse memory response = IClearingHouse(clearingHouse)
// 			.addLiquidity(
// 				IClearingHouse.AddLiquidityParams({
// 					baseToken: baseToken,
// 					base: base,
// 					quote: quote,
// 					lowerTick: _minTick,
// 					upperTick: _maxTick,
// 					minBase: 0, // TODO add min for slippage
// 					minQuote: 0,
// 					useTakerBalance: false, // this is not activated yet
// 					deadline: block.timestamp
// 				})
// 			);
// 		require(response.liquidity > 0, "0 liquidity added");

// 		// calculate shares and mint it
// 		uint256 shares;
// 		if (totalSupply() == 0) {
// 			shares = amount;
// 		} else {
// 			// share = amount / account value after liquidity is added
// 			shares = amount.mulDivDown(10**decimals(), _safeGetAccountValue());
// 		}
// 		_mint(receiver, shares);

// 		return shares;
// 	}

// 	function redeem(
// 		uint256 shares,
// 		address receiver,
// 		address owner
// 	) external nonReentrant returns (uint256) {
// 		// ratio = shares / totalSupply
// 		uint256 digits = 10**decimals();
// 		uint256 ratio = shares.mulDivDown(digits, totalSupply());
// 		require(allowance(owner, msg.sender) >= shares, "redeem amount exceeds allowance");
// 		_burn(owner, shares);

// 		// remove range order based on the ratio
// 		// (should always has 1 order and 0 taker position)
// 		IOrderBook orderBook = IOrderBook(IClearingHouse(clearingHouse).getOrderBook());
// 		uint128 liquidity = orderBook
// 			.getOpenOrder(address(this), baseToken, _minTick, _maxTick)
// 			.liquidity;
// 		uint256 liquidityOwnedByUser_256 = uint256(liquidity).mulDivDown(ratio, digits);
// 		uint128 liquidityOwnedByUser_128 = uint128(liquidityOwnedByUser_256);
// 		require(
// 			liquidityOwnedByUser_128 == liquidityOwnedByUser_256,
// 			"value doesn't fit in 128 bits"
// 		);
// 		IClearingHouse(clearingHouse).removeLiquidity(
// 			IClearingHouse.RemoveLiquidityParams({
// 				baseToken: baseToken,
// 				lowerTick: _minTick,
// 				upperTick: _maxTick,
// 				liquidity: liquidityOwnedByUser_128,
// 				minBase: 0,
// 				minQuote: 0,
// 				deadline: block.timestamp
// 			})
// 		);

// 		// close position
// 		IClearingHouse(clearingHouse).closePosition(
// 			IClearingHouse.ClosePositionParams({
// 				baseToken: baseToken,
// 				sqrtPriceLimitX96: 0, // no partial close
// 				oppositeAmountBound: 0, // TODO add min for slippage
// 				deadline: block.timestamp,
// 				referralCode: 0
// 			})
// 		);
// 		// if the position size is too large, taker position will be closed partially
// 		// TODO make withdraw 2 steps, auction or let keeper close it several times
// 		address accountBalance = IClearingHouse(clearingHouse).getAccountBalance();
// 		require(
// 			IAccountBalance(accountBalance).getTakerPositionSize(address(this), baseToken) == 0,
// 			"position size is too large"
// 		);

// 		// return asset
// 		uint256 accountValueOwnedByUser = _safeGetAccountValue().mulDivDown(ratio, digits);
// 		IVault(vault).withdraw(asset, accountValueOwnedByUser);
// 		SafeERC20.safeTransfer(IERC20(asset), receiver, accountValueOwnedByUser);
// 		return accountValueOwnedByUser;
// 	}

// 	function _safeGetAccountValue() internal view returns (uint256) {
// 		// account value is based on index price
// 		int256 accountValue = IVault(vault).getAccountValue(address(this));
// 		require(accountValue > 0, "bankrupt");
// 		return uint256(accountValue);
// 	}

// 	function _convertTokenDecimals(
// 		uint256 amount,
// 		uint8 fromDecimals,
// 		uint8 toDecimals
// 	) internal pure returns (uint256) {
// 		if (fromDecimals == toDecimals) {
// 			return amount;
// 		}
// 		return
// 			fromDecimals > toDecimals
// 				? amount / (10**(fromDecimals - toDecimals))
// 				: amount * (10**(toDecimals - fromDecimals));
// 	}
// }
