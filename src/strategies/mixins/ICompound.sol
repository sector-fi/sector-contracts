// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../../interfaces/compound/ICTokenInterfaces.sol";
import "../../interfaces/compound/IComptroller.sol";
import "../../interfaces/compound/ICompPriceOracle.sol";
import "../../interfaces/compound/IComptroller.sol";

import "../../interfaces/uniswap/IWETH.sol";

import "./ILending.sol";
import "./IBase.sol";

// import "hardhat/console.sol";

abstract contract ICompound is ILending {
	using SafeERC20 for IERC20;

	function cTokenLend() public view virtual returns (ICTokenErc20);

	function cTokenBorrow() public view virtual returns (ICTokenErc20);

	function oracle() public view virtual returns (ICompPriceOracle);

	function comptroller() public view virtual returns (IComptroller);

	function _enterMarket() internal {
		address[] memory cTokens = new address[](2);
		cTokens[0] = address(cTokenLend());
		cTokens[1] = address(cTokenBorrow());
		comptroller().enterMarkets(cTokens);
	}

	function _getCollateralFactor() internal view override returns (uint256) {
		(, uint256 collateralFactorMantissa, ) = ComptrollerV2Storage(address(comptroller()))
			.markets(address(cTokenLend()));
		return collateralFactorMantissa;
	}

	// TODO handle error
	function _redeem(uint256 amount) internal override {
		uint256 err = cTokenLend().redeemUnderlying(amount);
		// require(err == 0, "Compund: error redeeming underlying");
	}

	function _borrow(uint256 amount) internal override {
		cTokenBorrow().borrow(amount);

		// in case we need to wrap the tokens
		if (_isBase(1)) IWETH(address(short())).deposit{ value: amount }();
	}

	function _lend(uint256 amount) internal override {
		cTokenLend().mint(amount);
	}

	function _repay(uint256 amount) internal override {
		if (_isBase(1)) {
			// need to convert to base first
			IWETH(address(short())).withdraw(amount);

			// then repay in the base
			_repayBase(amount);
			return;
		}
		cTokenBorrow().repayBorrow(amount);
	}

	function _repayBase(uint256 amount) internal {
		ICTokenBase(address(cTokenBorrow())).repayBorrow{ value: amount }();
	}

	function _updateAndGetCollateralBalance() internal override returns (uint256) {
		return cTokenLend().balanceOfUnderlying(address(this));
	}

	function _getCollateralBalance() internal view override returns (uint256) {
		uint256 b = cTokenLend().balanceOf(address(this));
		return (b * cTokenLend().exchangeRateStored()) / 1e18;
	}

	function _updateAndGetBorrowBalance() internal override returns (uint256) {
		return cTokenBorrow().borrowBalanceCurrent(address(this));
	}

	function _getBorrowBalance() internal view override returns (uint256 shortBorrow) {
		shortBorrow = cTokenBorrow().borrowBalanceStored(address(this));
	}

	function _oraclePriceOfShort(uint256 amount) internal view override returns (uint256) {
		return
			(amount * oracle().getUnderlyingPrice(address(cTokenBorrow()))) /
			oracle().getUnderlyingPrice(address(cTokenLend()));
	}

	function _oraclePriceOfUnderlying(uint256 amount) internal view override returns (uint256) {
		return
			(amount * oracle().getUnderlyingPrice(address(cTokenLend()))) /
			oracle().getUnderlyingPrice(address(cTokenBorrow()));
	}

	function _maxBorrow() internal view virtual override returns (uint256) {
		return cTokenBorrow().getCash();
	}

	// returns true if either of the CTokens is cEth
	// index 0 = cTokenLend index 1 = cTokenBorrow
	function _isBase(uint8 index) internal virtual returns (bool) {}
}
