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
		uint256 performanceFee,
		uint256 managementFee,
		uint256 sharesFees,
		uint256 tvl
	);
	event MaxRedeemWindow(uint256 maxRedeemWindow);

	uint256 public totalChildHoldings;
	uint256 public floatAmnt; // amount of underlying tracked in vault
	uint256 public maxRedeemWindow; // time before emergency redeem becomes enabled

	function setMaxRedeemWindow(uint256 _maxRedeemWindow) public onlyOwner {
		maxRedeemWindow = _maxRedeemWindow;
		emit MaxRedeemWindow(_maxRedeemWindow);
	}

	function _harvest(uint256 currentChildHoldings) internal {
		// withdrawFromStrategies should be called prior to harvest to ensure this tx doesn't revert
		if (floatAmnt < pendingWithdraw) revert NotEnoughtFloat();

		uint256 profit = currentChildHoldings > totalChildHoldings
			? currentChildHoldings - totalChildHoldings
			: 0;

		uint256 timestamp = block.timestamp;
		uint256 tvl = currentChildHoldings + floatAmnt;

		// totalChildHoldings need to be updated before fees computation
		totalChildHoldings = currentChildHoldings;

		// PROCESS VAULT FEES
		uint256 _performanceFee = profit == 0 ? 0 : (profit * performanceFee) / 1e18;
		uint256 _managementFee = managementFee == 0
			? 0
			: (managementFee * tvl * (timestamp - lastHarvestTimestamp)) / 1e18 / 365 days;

		uint256 totalFees = _performanceFee + _managementFee;
		uint256 feeShares;

		if (totalFees > 0) {
			// this results in more accurate accounting considering dilution
			feeShares = totalFees.mulDivDown(totalSupply(), tvl - totalFees);
			_mint(treasury, feeShares);
		}

		emit Harvest(treasury, profit, _performanceFee, _managementFee, feeShares, tvl);

		// this enables withdrawals requested prior to this timestamp
		lastHarvestTimestamp = timestamp;
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

	error NotEnoughTimeSinceHarvest();
	error NotEnoughtFloat();
	error WrongUnderlying();
	error SlippageExceeded();
	error StrategyExists();
	error StrategyNotFound();
	error MissingDepositValue();
}
