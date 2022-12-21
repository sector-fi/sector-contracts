// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2, MultiCall } from "../../interfaces/gearbox/ICreditFacade.sol";
import { IPriceOracleV2 } from "../../interfaces/gearbox/IPriceOracleV2.sol";
import { IAddressProvider } from "../../interfaces/gearbox/IAddressProvider.sol";
import { StratAuth } from "../../common/StratAuth.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ICurvePool } from "../../interfaces/curve/ICurvePool.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "../../interfaces/uniswap/ISwapRouter.sol";

import "hardhat/console.sol";

contract stETH is StratAuth {
	using SafeERC20 for IERC20;

	ICreditFacade public constant creditFacade =
		ICreditFacade(0xC59135f449bb623501145443c70A30eE648Fa304);

	ICreditManagerV2 public immutable creditManager =
		ICreditManagerV2(creditFacade.creditManager());

	IPriceOracleV2 public immutable priceOracle =
		IPriceOracleV2(0x6385892aCB085eaa24b745a712C9e682d80FF681);

	ICurvePool public constant stETHAdapter =
		ICurvePool(0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef);

	ISwapRouter public constant uniswapV3Adapter =
		ISwapRouter(0xed5B30F8604c0743F167a19F42fEC8d284963a7D);

	// IAddressProvider addressProvider = IAddressProvider(0xcF64698AFF7E5f27A11dff868AF228653ba53be0);

	IERC20 public immutable underlying;
	IERC20 public immutable short = IERC20(creditFacade.underlying());

	IERC20 public constant stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

	bool hasOpenAccount;
	// leverage factor is how much we borrow in %
	// ex 2x leverage = 100, 3x leverage = 200
	uint16 public leverageFactor;
	uint256 immutable dec;
	uint256 constant ethDec = 1e18;
	address credAcc; // gearbox credit account // TODO can it expire?

	event SetVault(address indexed vault);

	constructor(
		AuthConfig memory authConfig,
		address _underlying,
		uint16 _leverageFactor
	) Auth(authConfig) {
		underlying = IERC20(_underlying);
		dec = 10**uint256(IERC20Metadata(address(underlying)).decimals());
		leverageFactor = _leverageFactor;
	}

	function setVault(address _vault) public onlyOwner {
		if (ISCYStrategy(_vault).underlying() != underlying) revert WrongVaultUnderlying();
		vault = _vault;
		emit SetVault(vault);
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of underlying to deposit
	function deposit(uint256 amount) public onlyVault returns (uint256) {
		// do we need granular approvals? or can we just approve once?
		// i.e. what happens after credit account is dilivered to someone else?
		underlying.approve(address(creditManager), amount);
		if (!hasOpenAccount) _openAccount(amount);
		else {
			/// TODO do we need to keep the account proportiona?
			/// or should we auto-rebalance towards our target leverage?
			uint256 borrowAmnt = underlyingToShort((amount * leverageFactor) / 100);
			creditFacade.addCollateral(address(this), address(underlying), amount);
			creditFacade.increaseDebt(borrowAmnt);
		}
		// returns added stETH
		uint256 startBalance = stETH.balanceOf(credAcc);
		_increasePosition();
		// our balance should allays increase on deposits
		return stETH.balanceOf(credAcc) - startBalance;
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of stETH to withdraw
	function redeem(uint256 amount, address to) public onlyVault returns (uint256) {
		/// there is no way to partially withdraw collateral
		/// we have to close account and re-open it :\
		uint256 fullStEthBal = _closePosition();
		uint256 uBalance = underlying.balanceOf(address(this));
		uint256 withdraw = (uBalance * amount) / fullStEthBal;

		(uint256 minBorrowed, ) = creditFacade.limits();
		uint256 minUnderlying = shortToUnderlying(minBorrowed) / leverageFactor;
		uint256 redeposit = uBalance > withdraw ? uBalance - withdraw : 0;

		// TODO handle how to deal with leftover underlying
		// return to SCY vault, but allow deposits?
		if (redeposit > minUnderlying) {
			console.log("re open", redeposit);
			_openAccount(uBalance - withdraw);
		}
		underlying.safeTransfer(to, withdraw);
		// creditFacade.
		return withdraw;
	}

	function _increasePosition() internal {
		// TODO: pass in the amnt of short?
		uint256 balance = short.balanceOf(credAcc);

		// slippage is check happens in the vault
		// 0 is ETH, 1 is stETH
		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(stETHAdapter),
			callData: abi.encodeWithSelector(ICurvePool.exchange.selector, 0, 1, balance, 0)
		});
		creditFacade.multicall(calls);
	}

	function closePosition() public onlyVault returns (uint256) {
		_closePosition();
		uint256 balance = underlying.balanceOf(address(this));
		underlying.safeTransfer(vault, balance);
		return balance;
	}

	/// return original stETH balance
	function _closePosition() internal returns (uint256) {
		uint256 stEthBalance = stETH.balanceOf(credAcc);
		// in practice exchange always returns this amount - 1 wei
		uint256 ethAmnt = stETHAdapter.get_dy(1, 0, stEthBalance) - 1;
		(, , uint256 borrowAmountWithInterestAndFees) = creditManager
			.calcCreditAccountAccruedInterest(credAcc);

		MultiCall[] memory calls;

		if (borrowAmountWithInterestAndFees < ethAmnt) {
			calls = new MultiCall[](1);
			calls[0] = MultiCall({
				target: address(stETHAdapter),
				callData: abi.encodeWithSelector(
					ICurvePool.exchange.selector,
					1,
					0,
					stEthBalance,
					0
				)
			});

			ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams(
				address(short),
				address(underlying),
				3000, // fee
				address(this),
				block.timestamp,
				ethAmnt - borrowAmountWithInterestAndFees,
				0, // minOut (check as total out on withdraw)
				type(uint160).max // price limit
			);

			// convert extra eth to underlying
			calls[1] = MultiCall({
				target: address(uniswapV3Adapter),
				callData: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params)
			});
		} else {
			calls = new MultiCall[](2);
			calls[0] = MultiCall({
				target: address(stETHAdapter),
				callData: abi.encodeWithSelector(
					ICurvePool.exchange.selector,
					1,
					0,
					stEthBalance,
					0
				)
			});

			// convert underlying to eth using uniswap v3
			ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
					address(underlying),
					address(short),
					3000, // fee
					address(this),
					block.timestamp,
					borrowAmountWithInterestAndFees - ethAmnt,
					type(uint256).max, // maxIn (check as total out on withdraw)
					0 // price limit
				);

			calls[1] = MultiCall({
				target: address(uniswapV3Adapter),
				callData: abi.encodeWithSelector(ISwapRouter.exactOutputSingle.selector, params)
			});
		}
		creditFacade.closeCreditAccount(address(this), 0, false, calls);
		return stEthBalance;
	}

	function _openAccount(uint256 amount) internal {
		underlying.approve(address(creditManager), amount);

		// todo oracle conversion from underlying to ETH
		uint256 borrowAmnt = underlyingToShort((amount * leverageFactor) / 100);

		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(creditFacade),
			callData: abi.encodeWithSelector(
				ICreditFacade.addCollateral.selector,
				address(this),
				underlying,
				amount
			)
		});

		creditFacade.openCreditAccountMulticall(borrowAmnt, address(this), calls, 0);
		credAcc = creditManager.getCreditAccountOrRevert(address(this));
		hasOpenAccount = true;
	}

	function convert(
		uint256 amount,
		address from,
		address to,
		uint256 fromDecimals,
		uint256 toDecimals
	) public view returns (uint256) {
		uint256 price = priceOracle.getPrice(from);
		uint256 price2 = priceOracle.getPrice(to);
		return (amount * price * toDecimals) / (price2 * fromDecimals);
	}

	function underlyingToShort(uint256 amount) public view returns (uint256) {
		return convert(amount, address(underlying), address(short), dec, ethDec);
	}

	function shortToUnderlying(uint256 amount) public view returns (uint256) {
		return convert(amount, address(short), address(underlying), ethDec, dec);
	}

	function getMaxTvl() public view returns (uint256) {
		/// TODO compute actual max tvl
		return type(uint256).max;
	}

	function collateralToUnderlying() public view returns (uint256) {
		return convert(1e18, address(stETH), address(underlying), ethDec, dec);
	}

	function collateralBalance() public view returns (uint256) {
		return stETH.balanceOf(credAcc);
	}

	function getPosition() public view returns (uint256 collateral, uint256 borrowed) {
		collateral = underlying.balanceOf(credAcc);
		borrowed = stETH.balanceOf(credAcc);
	}

	function getTotalTVL() public view returns (uint256) {
		if (!hasOpenAccount) return 0;
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		(uint256 totalAssets, ) = creditFacade.calcTotalValue(credAcc);
		if (totalOwed > totalAssets) return 0;
		return convert(totalAssets - totalOwed, address(stETH), address(underlying), ethDec, dec);
	}

	function getAndUpdateTVL() public view returns (uint256) {
		return getTotalTVL();
	}

	error WrongVaultUnderlying();
}
