// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC4626U, FixedPointMathLib, SafeERC20, FeeConfig, AuthConfig, IERC20 } from "../ERC4626/ERC4626U.sol";
import { IVaultStrategy } from "../../interfaces/IVaultStrategy.sol";
import { SectorBaseWEpochU } from "../ERC4626/SectorBaseWEpochU.sol";
import { VaultType, EpochType } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";
// TODO native asset deposit + flow

struct RedeemParams {
	IVaultStrategy strategy;
	VaultType vaultType;
	uint256 shares;
	uint256 minTokenOut;
}

struct DepositParams {
	IVaultStrategy strategy;
	VaultType vaultType;
	uint256 amountIn;
	uint256 minSharesOut;
}

// Sector Aggregator Vault
contract AggregatorWEpochVaultU is SectorBaseWEpochU {
	using FixedPointMathLib for uint256;
	using SafeERC20 for IERC20;

	/// if vaults accepts native asset we set asset to address 0;
	address internal constant NATIVE = address(0);

	// resonable amount to not go over gas limit when doing emergencyWithdraw
	// in reality can go up to 200
	uint8 constant MAX_STRATS = 100;

	mapping(IVaultStrategy => bool) public strategyExists;
	address[] public strategyIndex;

	function initialize(
		IERC20 asset_,
		string memory _name,
		string memory _symbol,
		bool _useNativeAsset,
		uint256 _harvestInterval,
		uint256 _maxTvl,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig
	) public initializer {
		__ERC4626_init(asset_, _name, _symbol, _useNativeAsset);
		__Auth_init(authConfig);
		__Fees_init(feeConfig);

		maxTvl = _maxTvl;
		emit MaxTvlUpdated(_maxTvl);

		harvestInterval = _harvestInterval;
		emit SetHarvestInterval(_harvestInterval);

		lastHarvestTimestamp = block.timestamp;
	}

	function getMaxTvl() external view returns (uint256) {
		uint256 startMaxTvl;
		for (uint256 i = 0; i < strategyIndex.length; i++) {
			IVaultStrategy strategy = IVaultStrategy(strategyIndex[i]);
			startMaxTvl += strategy.getMaxTvl();
		}
		return maxTvl < startMaxTvl ? maxTvl : startMaxTvl;
	}

	function addStrategy(IVaultStrategy strategy) public onlyOwner {
		if (strategyIndex.length >= MAX_STRATS) revert TooManyStrategies();
		if (strategyExists[strategy]) revert StrategyExists();

		/// make sure underlying matches
		if (address(strategy.underlying()) != address(asset)) revert WrongUnderlying();
		if (strategy.epochType() != epochType) revert WrongEpochType();

		strategyExists[strategy] = true;
		strategyIndex.push(address(strategy));
		emit AddStrategy(address(strategy));
	}

	function removeStrategy(IVaultStrategy strategy) public onlyOwner {
		if (!strategyExists[strategy]) revert StrategyNotFound();
		strategyExists[strategy] = false;

		// make sure we don't have deposits in the strategy
		uint256 balance = strategy.balanceOf(address(this));
		if (balance > MIN_LIQUIDITY) revert StrategyHasBalance();

		uint256 length = strategyIndex.length;
		// replace current index with last strategy and pop the index array
		uint256 i;
		for (i; i < length; ++i) if (address(strategy) == strategyIndex[i]) break;
		strategyIndex[i] = strategyIndex[length - 1];
		strategyIndex.pop();
		emit RemoveStrategy(address(strategy));
	}

	function totalStrategies() external view returns (uint256) {
		return strategyIndex.length;
	}

	function getAllStrategies() external view returns (address[] memory) {
		return strategyIndex;
	}

	/// We compute expected tvl off-chain first, to ensure this transactions isn't sandwitched
	function harvest(uint256 expectedTvl, uint256 maxDelta) public onlyRole(MANAGER) {
		uint256 currentChildHoldings = _getStrategyHoldings();
		uint256 tvl = currentChildHoldings + floatAmnt;
		_checkSlippage(expectedTvl, tvl, maxDelta);
		// harvest event emitted here
		_harvest(currentChildHoldings);
	}

	/// this can be done in parts in case gas limit is reached
	function depositIntoStrategies(DepositParams[] calldata params) public onlyRole(MANAGER) {
		uint256 l = params.length;
		for (uint256 i; i < l; ++i) {
			DepositParams memory param = params[i];
			uint256 amountIn = param.amountIn;
			if (amountIn == 0) continue;
			IVaultStrategy strategy = param.strategy;

			if (!strategyExists[strategy]) revert StrategyNotFound();

			// update underlying float accouting
			beforeWithdraw(amountIn, 0);
			/// push funds to avoid approvals
			if (param.vaultType == VaultType.Strategy) {
				// send funds - more gas efficient
				if (strategy.sendERC20ToStrategy() == true)
					asset.safeTransfer(strategy.strategy(), amountIn);
				else asset.safeTransfer(address(strategy), amountIn);

				// process deposit
				strategy.deposit(address(this), address(asset), 0, param.minSharesOut);
			} else if (param.vaultType == VaultType.Aggregator) {
				asset.safeApprove(address(strategy), amountIn);
				strategy.deposit(amountIn, address(this));
			}
			totalChildHoldings += amountIn;

			emit DepositIntoStrategy(msg.sender, address(strategy), amountIn);
		}
	}

	function requestRedeemFromStrategies(RedeemParams[] calldata params) public onlyRole(MANAGER) {
		uint256 l = params.length;
		for (uint256 i; i < l; ++i) {
			// appropriate vault check should happen on front end
			params[i].strategy.requestRedeem(params[i].shares);
		}
	}

	/// this can be done in parts in case gas limit is reached
	function withdrawFromStrategies(RedeemParams[] calldata params) public onlyRole(MANAGER) {
		uint256 l = params.length;
		for (uint256 i; i < l; ++i) {
			RedeemParams memory param = params[i];
			uint256 shares = param.shares;
			if (shares == 0) continue;
			IVaultStrategy strategy = param.strategy;
			if (!strategyExists[strategy]) revert StrategyNotFound();

			uint256 amountOut;
			if (param.vaultType == VaultType.Strategy)
				// no need to push share tokens - contract can burn them
				amountOut = strategy.redeem(
					address(this),
					shares,
					address(asset), // token out is allways asset
					param.minTokenOut
				);
			else if (param.vaultType == VaultType.Aggregator) amountOut = strategy.redeem();

			// if strategy was profitable, we may end up withdrawing more than totalChildHoldings
			totalChildHoldings = amountOut > totalChildHoldings
				? 0
				: totalChildHoldings - amountOut;

			// update underlying float accounting
			afterDeposit(amountOut, 0);
			emit WithdrawFromStrategy(msg.sender, address(strategy), amountOut);
		}
	}

	/// @dev this method allows direct redemption of shares in exchange for
	/// a portion of the float amount + a portion of all the strategy shares the vault holds
	function emergencyRedeem() public nonReentrant {
		uint256 shares = balanceOf(msg.sender);
		if (shares == 0) return;

		// pendingRedeem cannot be bigger than totalSupply
		uint256 adjustedSupply = totalSupply() - pendingRedeem;

		// redeem proportional share of vault's underlying float balance
		// (minus pendingWithdraw)
		uint256 pendingWithdraw = convertToAssets(pendingRedeem);

		if (floatAmnt > pendingWithdraw) {
			uint256 availableFloat = floatAmnt - pendingWithdraw;
			uint256 underlyingShare = (availableFloat * shares) / adjustedSupply;
			beforeWithdraw(underlyingShare, 0);
			asset.safeTransfer(msg.sender, underlyingShare);
		}

		uint256 l = strategyIndex.length;

		// redeem proportional share of each strategy
		for (uint256 i; i < l; ++i) {
			IERC20 stratToken = IERC20(strategyIndex[i]);
			uint256 balance = stratToken.balanceOf(address(this));
			uint256 userShares = (shares * balance) / adjustedSupply;
			if (userShares == 0) continue;
			stratToken.safeTransfer(msg.sender, userShares);
		}

		// reduce the amount of totalChildHoldings
		totalChildHoldings -= (shares * totalChildHoldings) / adjustedSupply;

		_burn(msg.sender, shares);
	}

	/// gets accurate strategy holdings denominated in asset
	function _getStrategyHoldings() internal returns (uint256 tvl) {
		uint256 l = strategyIndex.length;
		/// TODO compute realistic limit for strategy array lengh to stay within gas limit
		for (uint256 i; i < l; ++i) {
			IVaultStrategy strategy = IVaultStrategy(payable(strategyIndex[i]));
			tvl += strategy.getUpdatedUnderlyingBalance(address(this));
		}
	}

	/// returns expected tvl (used for estimate)
	function getTvl() public view returns (uint256 tvl) {
		uint256 l = strategyIndex.length;
		// there should be no untrusted strategies in this array
		for (uint256 i; i < l; ++i) {
			IVaultStrategy strategy = IVaultStrategy(payable(strategyIndex[i]));
			tvl += strategy.underlyingBalance(address(this));
		}
		tvl += asset.balanceOf(address(this));
	}

	function totalAssets() public view virtual override returns (uint256) {
		return floatAmnt + totalChildHoldings;
	}

	function getFloat() public view returns (uint256) {
		return floatAmnt - convertToAssets(pendingRedeem);
	}

	/// INTERFACE UTILS

	/// @dev returns accurate value used to estimate current value
	function estimateUnderlyingBalance(address user) external view returns (uint256) {
		uint256 shares = balanceOf(user);
		// value based on last harvest exchange rate
		uint256 cachedValue = convertToAssets(shares);
		// valued based on current tvl
		uint256 currentValue = sharesToUnderlying(shares);
		return cachedValue > currentValue ? currentValue : cachedValue;
	}

	/// @dev current exchange rate (different from previewDeposit rate)
	/// this should be used for estiamtes of withdrawals
	function sharesToUnderlying(uint256 shares) public view returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
		return supply == 0 ? shares : shares.mulDivDown(getTvl(), supply);
	}

	/// @dev current exchange rate (different from previewDeposit / previewWithdrawal rate)
	/// this should be used estimate of deposit fee
	function underlyingToShares(uint256 underlyingAmnt) public view returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
		return supply == 0 ? underlyingAmnt : underlyingAmnt.mulDivDown(supply, getTvl());
	}

	event AddStrategy(address indexed strategy);
	event RemoveStrategy(address indexed strategy);
	event DepositIntoStrategy(address caller, address strategy, uint256 amount);
	event WithdrawFromStrategy(address caller, address strategy, uint256 amount);
}
