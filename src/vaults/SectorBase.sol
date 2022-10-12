// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20 } from "./ERC4626/ERC4626.sol";
import { ISCYStrategy } from "../interfaces/scy/ISCYStrategy.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

abstract contract SectorBase is BatchedWithdraw, XChainIntegrator {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;

	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 underlyingFees,
		uint256 sharesFees
	);

	uint256 public totalChildHoldings;
	uint256 public floatAmnt; // amount of underlying tracked in vault

	function _harvest(uint256 currentChildHoldings) internal {
		uint256 profit = currentChildHoldings > totalChildHoldings
			? currentChildHoldings - totalChildHoldings
			: 0;

		// if we suffered losses, update totalChildHoldings BEFORE _processWithdraw
		if (totalChildHoldings > currentChildHoldings) totalChildHoldings = currentChildHoldings;

		// process withdrawals if we have enough balance
		// withdrawFromStrategies should be called before this
		// note we are using the totalChildHoldings from previous harvest if there is a profit
		// this prevents harvest front-running and adds a dynamic fee to withdrawals
		if (pendingWithdraw != 0) {
			// pending withdrawals are removed from available deposits
			// availableDeposits -= pendingWithdrawal;
			_processWithdraw();
			if (floatAmnt < pendingWithdraw) revert NotEnoughtFloat();
		}

		// take vault fees
		if (profit == 0) {
			emit Harvest(treasury, 0, 0, 0);
			return;
		}

		// since profit > 0 we have not updated totalChildHoldings yet
		totalChildHoldings = currentChildHoldings;
		uint256 underlyingFees = (profit * performanceFee) / 1e18;

		// this results in more accurate accounting considering dilution
		uint256 feeShares = toSharesAfterDeposit(underlyingFees);

		emit Harvest(treasury, profit, underlyingFees, feeShares);
		_mint(treasury, feeShares);
	}

	function _checkSlippage(
		uint256 expectedValue,
		uint256 actualValue,
		uint256 maxDelta
	) internal pure {
		uint256 delta = expectedValue > actualValue
			? expectedValue - actualValue
			: actualValue - expectedValue;
		if (delta > maxDelta) revert SlippageExceeded();
	}

	function totalAssets() public view virtual override returns (uint256) {
		return floatAmnt + totalChildHoldings;
	}

	/// INTERFACE UTILS

	/// @dev returns a cached value used for withdrawals
	function underlyingBalance(address user) public view returns (uint256) {
		uint256 shares = balanceOf(user);
		return convertToAssets(shares);
	}

	function underlyingDecimals() public view returns (uint8) {
		return asset.decimals();
	}

	function underlying() public view returns (address) {
		return address(asset);
	}

	/// OVERRIDES

	function afterDeposit(uint256 assets, uint256) internal override {
		floatAmnt += assets;
	}

	function beforeWithdraw(uint256 assets, uint256) internal override {
		// this check prevents withdrawing more underlying from the vault then
		// what we need to keep to honor withdrawals
		if (floatAmnt < assets || floatAmnt - assets < pendingWithdraw) revert NotEnoughtFloat();
		floatAmnt -= assets;
	}

	event RegisterDeposit(uint256 total);
	event EmergencyWithdraw(address vault, address client, uint256 shares);

	error NotEnoughtFloat();
	error WrongUnderlying();
	error SlippageExceeded();
	error StrategyExists();
	error StrategyNotFound();
	error MissingDepositValue();
}
