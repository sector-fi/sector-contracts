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

contract LevEth is StratAuth {
	ICreditFacade public immutable creditFacade;
	ICreditManagerV2 public immutable creditManager;
	IPriceOracleV2 public immutable priceOracle;

	ICurvePool public immutable curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

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
		if (!hasOpenAccount) openAccount(amount);
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
	function withdraw(uint256 amount) public onlyVault {
		uint256 ethAmnt = _decreasePosition(amount);
		// uint currentLeverage =
	}

	function _increasePosition() internal returns (uint256) {
		// TODO: pass in the amnt of short?
		uint256 balance = short.balanceOf(address(this));
		IWETH(address(short)).withdraw(balance);

		// slipage is check happens in the vault
		// 0 is ETH, 1 is stETH
		// returns amount of stETH
		return curvePool.exchange(0, 1, balance, 0);
	}

	/// amount of stETH to withdraw
	function _decreasePosition(uint256 amount) internal returns (uint256) {
		// TODO: pass in the amnt of short?

		// slipage is check happens in the vault
		// 0 is ETH, 1 is stETH
		uint256 ethAmnt = curvePool.exchange(1, 0, amount, 0);
		// return eth via payable
		// IWETH(address(short)).deposit{ value: ethAmnt }();
		return ethAmnt;
	}

	function openAccount(uint256 amount) public {
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
		hasOpenAccount = true;
	}

	function underlyingToShort(uint256 amount) public view returns (uint256) {
		return
			(amount * ethDec * priceOracle.getPrice(address(underlying))) /
			priceOracle.getPrice(address(short)) /
			dec;
	}

	function shortToUnderlying(uint256 amount) public view returns (uint256) {
		return
			(amount * dec * priceOracle.getPrice(address(short))) /
			priceOracle.getPrice(address(underlying)) /
			(ethDec);
	}

	error WrongVaultUnderlying();
}
