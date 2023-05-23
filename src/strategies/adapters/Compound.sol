// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ICTokenErc20 } from "../../interfaces/compound/ICTokenInterfaces.sol";
import { IComptroller } from "../../interfaces/compound/IComptroller.sol";
import { ICompPriceOracle } from "../../interfaces/compound/ICompPriceOracle.sol";
import { IComptroller, ComptrollerV1Storage } from "../../interfaces/compound/IComptroller.sol";

import { ICompound, SafeERC20, IERC20 } from "../mixins/ICompound.sol";

// import "hardhat/console.sol";

abstract contract Compound is ICompound {
	using SafeERC20 for IERC20;

	ICTokenErc20 private _cTokenLend;
	ICTokenErc20 private _cTokenBorrow;

	IComptroller private _comptroller;
	ICompPriceOracle private _oracle;

	constructor(
		address comptroller_,
		address cTokenLend_,
		address cTokenBorrow_
	) {
		_cTokenLend = ICTokenErc20(cTokenLend_);
		_cTokenBorrow = ICTokenErc20(cTokenBorrow_);
		_comptroller = IComptroller(comptroller_);
		_oracle = ICompPriceOracle(ComptrollerV1Storage(comptroller_).oracle());
		_enterMarket();
		_addLendingApprovals();
	}

	function _addLendingApprovals() internal override {
		// ensure USDC approval - assume we trust USDC
		underlying().safeIncreaseAllowance(address(_cTokenLend), type(uint256).max);
		short().safeIncreaseAllowance(address(_cTokenBorrow), type(uint256).max);
	}

	function cTokenLend() public view override returns (ICTokenErc20) {
		return _cTokenLend;
	}

	function cTokenBorrow() public view override returns (ICTokenErc20) {
		return _cTokenBorrow;
	}

	function oracle() public view override returns (ICompPriceOracle) {
		return _oracle;
	}

	function comptroller() public view override returns (IComptroller) {
		return _comptroller;
	}
}
