// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20 } from "./ERC4626/ERC4626.sol";
import { ISCYStrategy } from "../interfaces/scy/ISCYStrategy.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";

// import "hardhat/console.sol";

// TODO native asset deposit + flow

struct RedeemParams {
	ISCYStrategy strategy;
	uint256 amountSharesToRedeem;
	uint256 minTokenOut;
}

struct DepositParams {
	ISCYStrategy strategy;
	uint256 amountIn;
	uint256 minSharesOut;
}

contract SectorVault is ERC4626, BatchedWithdraw {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;

	event Harvest(
		address indexed treasury,
		uint256 underlyingProfit,
		uint256 underlyingFees,
		uint256 sharesFees,
		uint256 strategyTvl
	);

	/// if vaults accepts native asset we set asset to address 0;
	address internal constant NATIVE = address(0);

	mapping(ISCYStrategy => bool) public strategyExists;
	address[] strategyIndex;
	uint256 totalStrategyHoldings;

	constructor(
		ERC20 asset_,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee
	) ERC4626(asset_, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {}

	function addStrategy(ISCYStrategy strategy) public onlyOwner {
		if (strategyExists[strategy]) revert StrategyExists();

		/// make sure underlying matches
		if (address(strategy.underlying()) != address(_asset)) revert WrongUnderlying();

		strategyExists[strategy] = true;
		strategyIndex.push(address(strategy));
	}

	function removeStrategy(ISCYStrategy strategy) public onlyOwner {
		if (!strategyExists[strategy]) revert StrategyNotFound();
		strategyExists[strategy] = false;
		uint256 length = strategyIndex.length;
		// replace current index with last strategy and pop the index array
		for (uint256 i; i <= length; i++) {
			if (address(strategy) == strategyIndex[i]) {
				strategyIndex[i] = strategyIndex[length - 1];
				strategyIndex.pop();
				continue;
			}
		}
	}

	/// We compute expected tvl off-chain first, to ensure this transactions isn't sandwitched
	function harvest(uint256 expectedTvl, uint256 maxDelta) public onlyRole(MANAGER) {
		uint256 tvl = _getStrategyHoldings();
		_checkSlippage(expectedTvl, tvl, maxDelta);

		uint256 profit = tvl > totalStrategyHoldings ? tvl - totalStrategyHoldings : 0;

		// if we suffered losses, update totalStrategyHoldings BEFORE _processWithdraw
		if (totalStrategyHoldings > tvl) totalStrategyHoldings = tvl;

		// process withdrawals if we have enough balance
		// withdrawFromStrategies should be called before this
		// note we are using the totalStrategyHoldings from previous harvest if there is a profit
		// this prevents harvest front-running and adds a dynamic fee to withdrawals
		if (pendingWithdrawal != 0 && pendingWithdrawal < ERC20(_asset).balanceOf(address(this)))
			_processWithdraw(convertToShares(1e18));

		// take vault fees
		if (profit == 0) {
			emit Harvest(treasury, 0, 0, 0, tvl);
			return;
		}

		// since profit > 0 we have not updated totalStrategyHoldings yet
		totalStrategyHoldings = tvl;
		uint256 underlyingFees = (profit * performanceFee) / 1e18;
		uint256 feeShares = convertToShares(underlyingFees);

		emit Harvest(treasury, profit, underlyingFees, feeShares, tvl);
		_mint(treasury, feeShares);
	}

	/// this can be done in parts in case gas limit is reached
	function withdrawFromStrategies(RedeemParams[] calldata params) public onlyRole(MANAGER) {
		for (uint256 i; i <= params.length; i++) {
			RedeemParams memory param = params[i];
			ISCYStrategy strategy = param.strategy;
			// no need to push share tokens - contract can burn them
			uint256 amountOut = strategy.redeem(
				address(this),
				param.amountSharesToRedeem,
				address(_asset), // token out is allways asset
				param.minTokenOut
			);
			totalStrategyHoldings -= amountOut;
		}
	}

	/// this can be done in parts in case gas limit is reached
	function despositIntoStrategies(DepositParams[] calldata params) public onlyRole(MANAGER) {
		for (uint256 i; i <= params.length; i++) {
			DepositParams memory param = params[i];
			ISCYStrategy strategy = param.strategy;
			/// push funds to avoid approvals
			ERC20(_asset).safeTransfer(strategy.strategy(), param.amountIn);
			uint256 sharesOut = strategy.deposit(
				address(this),
				address(_asset),
				param.amountIn,
				param.minSharesOut
			);
			totalStrategyHoldings += param.amountIn;
		}
	}

	/// gets accurate strategy holdings denominated in asset
	function _getStrategyHoldings() internal returns (uint256 tvl) {
		uint256 lastIndex = strategyIndex.length - 1;
		/// TODO compute realistic limit for strategy array lengh to stay within gas limit
		for (uint256 i; i <= lastIndex; i++) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.getAndUpdateTvl();
		}
	}

	function _checkSlippage(
		uint256 expectedValue,
		uint256 actualValue,
		uint256 maxDelta
	) internal pure {
		uint256 delta = expectedValue > actualValue
			? expectedValue - actualValue
			: actualValue - actualValue;
		if (delta > maxDelta) revert SlippageExceeded();
	}

	/// returns expected tvl (used for estimate)
	function getTvl() public view returns (uint256 tvl) {
		uint256 length = strategyIndex.length;
		// there should be no untrusted strategies in this array
		for (uint256 i; i < length; i++) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.getTvl();
		}
	}

	function totalAssets() public view virtual override returns (uint256) {
		return _asset.balanceOf(address(this)) + totalStrategyHoldings;
	}

	/// OVERRIDES

	function withdraw(
		uint256 assets,
		address receiver,
		address owner
	) public pure override(ERC4626, BatchedWithdraw) returns (uint256 shares) {
		return super.withdraw(assets, receiver, owner);
	}

	function redeem(
		uint256 shares,
		address receiver,
		address owner
	) public virtual override(ERC4626, BatchedWithdraw) returns (uint256 assets) {
		return super.redeem(shares, receiver, owner);
	}

	error WrongUnderlying();
	error SlippageExceeded();
	error StrategyExists();
	error StrategyNotFound();
}
