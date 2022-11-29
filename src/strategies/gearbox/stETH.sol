// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICreditFacade, ICreditManagerV2, MultiCall } from "interfaces/gearbox/ICreditFacade.sol";
import { IPriceOracleV2 } from "../../interfaces/gearbox/IPriceOracleV2.sol";
import { IAddressProvider } from "../../interfaces/gearbox/IAddressProvider.sol";
import { StratAuth } from "../../common/StratAuth.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ICurvePool } from "../../interfaces/curve/ICurvePool.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";

contract stETH is StratAuth {
	ICreditFacade public immutable creditFacade;
	ICreditManagerV2 public immutable creditManager;
	IPriceOracleV2 public immutable priceOracle;

	ICurvePool public constant stETHAdapter =
		ICurvePool(0x0Ad2Fc10F677b2554553DaF80312A98ddb38f8Ef);

	// IAddressProvider addressProvider = IAddressProvider(0xcF64698AFF7E5f27A11dff868AF228653ba53be0);

	IERC20 public immutable underlying;
	IERC20 public immutable short;

	IERC20 public immutable stETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

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
		address _creditFacade,
		address _underlying,
		address _priceOracle,
		uint16 _leverageFactor
	) Auth(authConfig) {
		creditFacade = ICreditFacade(_creditFacade);
		creditManager = ICreditManagerV2(creditFacade.creditManager());
		underlying = IERC20(_underlying);
		dec = 10**uint256(IERC20Metadata(address(underlying)).decimals());
		short = IERC20(creditFacade.underlying());
		leverageFactor = _leverageFactor;
		priceOracle = IPriceOracleV2(_priceOracle);
	}

	function setVault(address _vault) public onlyOwner {
		if (ISCYStrategy(vault).underlying() != underlying) revert WrongVaultUnderlying();
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
			creditFacade.addCollateral(vault, address(underlying), amount);
			creditFacade.increaseDebt(borrowAmnt);
		}
		// returns added stETH
		return _increasePosition();
	}

	/// @notice deposits underlying into the strategy
	/// @param amount amount of stETH to withdraw
	function redeem(uint256 amount, address to) public onlyVault returns (uint256) {
		/// there is no way to partially withdraw collateral
		/// we have to close account and re-open it :\
		uint256 fullStEthBal = _closePosition();
		uint256 uBalance = underlying.balanceOf(address(this));
		uint256 withdraw = (uBalance * amount) / fullStEthBal;
		_openAccount(uBalance - withdraw);
		// creditFacade.
		return withdraw;
	}

	function _increasePosition() internal returns (uint256 stETHAmnt) {
		// TODO: pass in the amnt of short?
		uint256 balance = short.balanceOf(credAcc);

		// slipage is check happens in the vault
		// 0 is ETH, 1 is stETH
		stETHAmnt = stETHAdapter.get_dy(0, 1, balance);
		MultiCall[] memory calls = new MultiCall[](1);
		calls[0] = MultiCall({
			target: address(stETHAdapter),
			callData: abi.encodeWithSelector(ICurvePool.exchange.selector, 0, 1, balance, 0)
		});
		creditFacade.multicall(calls);
	}

	function closePosition() public onlyVault returns (uint256) {
		_closePosition();
		return underlying.balanceOf(address(this));
	}

	/// return original stETH balance
	function _closePosition() internal returns (uint256) {
		uint256 stEthBalance = stETH.balanceOf(credAcc);
		uint256 ethAmnt = stETHAdapter.get_dy(0, 1, stEthBalance);
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
		} else {
			/// TODO we may need to trade some of USDC for ETH as well
			/// uniswap v3 swap
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
				vault,
				underlying,
				amount
			)
		});

		creditFacade.openCreditAccountMulticall(borrowAmnt, vault, calls, 0);
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
		return (amount * price * 10**toDecimals) / (price2 * 10**fromDecimals);
	}

	function underlyingToShort(uint256 amount) public view returns (uint256) {
		return convert(amount, address(underlying), address(short), dec, ethDec);
	}

	// function shortToUnderlying(uint256 amount) public view returns (uint256) {
	// 	return
	// 		(amount * dec * priceOracle.getPrice(address(short))) /
	// 		priceOracle.getPrice(address(underlying)) /
	// 		(ethDec);
	// }

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
		(, , uint256 totalOwed) = creditManager.calcCreditAccountAccruedInterest(credAcc);
		(uint256 totalAssets, ) = creditFacade.calcTotalValue(credAcc);
		uint256 uPrice = priceOracle.getPrice(address(underlying));
		return (((totalAssets - totalOwed) * 1e8) / uPrice) * dec;
	}

	function getAndUpdateTVL() public view returns (uint256) {
		return getTotalTVL();
	}

	error WrongVaultUnderlying();
}
