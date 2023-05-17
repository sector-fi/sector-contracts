// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPool } from "./interfaces/IPool.sol";

import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";

import { ILending } from "../../mixins/ILending.sol";
import { IBase } from "../../mixins/IBase.sol";

import { IAToken } from "./interfaces/IAToken.sol";
import { IAaveOracle } from "./interfaces/IAaveOracle.sol";
import { IPoolAddressesProvider } from "./interfaces/IPoolAddressesProvider.sol";

import { DataTypes, ReserveConfiguration } from "./libraries/ReserveConfiguration.sol";

// import "hardhat/console.sol";

abstract contract AaveModule is ILending {
	using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
	using SafeERC20 for IERC20;

	uint256 public constant INTEREST_RATE_MODE_VARIABLE = 2;

	using SafeERC20 for IERC20;

	/// @dev aToken
	IAToken private _cTokenLend;
	/// @dev aave DEBT token
	IAToken private _cTokenBorrow;
	IAToken private _debtToken;

	/// @dev aave pool
	IPool private _comptroller;
	IAaveOracle private _oracle;

	uint16 public uDec;
	uint16 public sDec;

	constructor(
		address comptroller_,
		address cTokenLend_,
		address cTokenBorrow_
	) {
		_cTokenLend = IAToken(cTokenLend_);
		_cTokenBorrow = IAToken(cTokenBorrow_);
		_comptroller = IPool(comptroller_);
		IPoolAddressesProvider addrsProv = IPoolAddressesProvider(
			_comptroller.ADDRESSES_PROVIDER()
		);
		_oracle = IAaveOracle(addrsProv.getPriceOracle());

		DataTypes.ReserveData memory reserveData = _comptroller.getReserveData(address(short()));
		_debtToken = IAToken(reserveData.variableDebtTokenAddress);
		_addLendingApprovals();

		uDec = IERC20Metadata(address(underlying())).decimals();
		sDec = IERC20Metadata(address(short())).decimals();
	}

	function _addLendingApprovals() internal override {
		// ensure USDC approval - assume we trust USDC
		underlying().safeIncreaseAllowance(address(_comptroller), type(uint256).max);
		short().safeIncreaseAllowance(address(_comptroller), type(uint256).max);
	}

	/// @dev aToken
	function cTokenLend() public view returns (IAToken) {
		return _cTokenLend;
	}

	/// @dev aave DEBT token
	function cTokenBorrow() public view returns (IAToken) {
		return _cTokenBorrow;
	}

	function oracle() public view returns (IAaveOracle) {
		return _oracle;
	}

	/// @dev technically pool
	function comptroller() public view returns (IPool) {
		return _comptroller;
	}

	function _redeem(uint256 amount) internal override {
		// TODO handle native underlying?
		comptroller().withdraw(address(underlying()), amount, address(this));
	}

	function _borrow(uint256 amount) internal override {
		comptroller().borrow(
			address(short()),
			amount,
			INTEREST_RATE_MODE_VARIABLE, // TODO should we use stable ever?
			0,
			address(this)
		);
	}

	function _lend(uint256 amount) internal override {
		// TODO handle native underlying?
		comptroller().supply(address(underlying()), amount, address(this), 0);
		comptroller().setUserUseReserveAsCollateral(address(underlying()), true);
	}

	function _repay(uint256 amount) internal override {
		comptroller().repay(address(short()), amount, INTEREST_RATE_MODE_VARIABLE, address(this));
	}

	/// TODO do we need to call update?
	function _updateAndGetCollateralBalance() internal override returns (uint256) {
		return _cTokenLend.balanceOf(address(this));
	}

	function _getCollateralBalance() internal view override returns (uint256) {
		return _cTokenLend.balanceOf(address(this));
	}

	function _updateAndGetBorrowBalance() internal override returns (uint256) {
		return _debtToken.balanceOf(address(this));
	}

	function _getBorrowBalance() internal view override returns (uint256 shortBorrow) {
		return _debtToken.balanceOf(address(this));
	}

	function _getCollateralFactor() internal view override returns (uint256) {
		uint256 ltv = comptroller().getConfiguration(address(underlying())).getLtv();
		return (ltv * 1e18) / 10000;
	}

	function _oraclePriceOfShort(uint256 amount) internal view override returns (uint256) {
		return
			((amount * oracle().getAssetPrice(address(short()))) * (10**uDec)) /
			oracle().getAssetPrice(address(underlying())) /
			(10**sDec);
	}

	function _oraclePriceOfUnderlying(uint256 amount) internal view override returns (uint256) {
		return
			((amount * oracle().getAssetPrice(address(underlying()))) * (10**sDec)) /
			oracle().getAssetPrice(address(short())) /
			(10**uDec);
	}

	function _maxBorrow() internal view virtual override returns (uint256) {
		uint256 maxBorrow = short().balanceOf(address(cTokenBorrow()));
		(uint256 borrowCap, ) = comptroller().getConfiguration(address(short())).getCaps();
		borrowCap = borrowCap * (10**sDec);
		uint256 borrowBalance = _debtToken.totalSupply();
		uint256 maxBorrowCap = borrowCap - borrowBalance;
		return maxBorrow > maxBorrowCap ? maxBorrowCap : maxBorrow;
	}
}
