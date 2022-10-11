// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20 } from "./ERC4626/ERC4626.sol";
import { ISCYStrategy } from "../interfaces/scy/ISCYStrategy.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

// TODO native asset deposit + flow

struct RedeemParams {
	ISCYStrategy strategy;
	uint256 shares;
	uint256 minTokenOut;
}

struct DepositParams {
	ISCYStrategy strategy;
	uint256 amountIn;
	uint256 minSharesOut;
}

contract SectorVault is ERC4626, BatchedWithdraw, XChainIntegrator {
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

	uint256 public totalStrategyHoldings;
	uint256 public floatAmnt; // amount of underlying tracked in vault

	address[] bridgeQueue;
	uint256 balanceBeforeCrossDeposit = 0;

	constructor(
		ERC20 asset_,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee,
		address _postOffice
	)
		ERC4626(asset_, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee)
		XChainIntegrator(_postOffice)
	{}

	function addStrategy(ISCYStrategy strategy) public onlyOwner {
		if (strategyExists[strategy]) revert StrategyExists();

		/// make sure underlying matches
		if (address(strategy.underlying()) != address(asset)) revert WrongUnderlying();

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
		uint256 updatedStratHoldings = _getStrategyHoldings();
		uint256 tvl = updatedStratHoldings + asset.balanceOf(address(this));
		_checkSlippage(expectedTvl, tvl, maxDelta);

		uint256 profit = updatedStratHoldings > totalStrategyHoldings
			? updatedStratHoldings - totalStrategyHoldings
			: 0;

		// if we suffered losses, update totalStrategyHoldings BEFORE _processWithdraw
		if (totalStrategyHoldings > updatedStratHoldings)
			totalStrategyHoldings = updatedStratHoldings;

		// process withdrawals if we have enough balance
		// withdrawFromStrategies should be called before this
		// note we are using the totalStrategyHoldings from previous harvest if there is a profit
		// this prevents harvest front-running and adds a dynamic fee to withdrawals
		if (pendingWithdraw != 0) {
			// pending withdrawals are removed from available deposits
			// availableDeposits -= pendingWithdrawal;
			_processWithdraw();
			if (floatAmnt < pendingWithdraw) revert NotEnoughtFloat();
		}

		// take vault fees
		if (profit == 0) {
			emit Harvest(treasury, 0, 0, 0, tvl);
			return;
		}

		// since profit > 0 we have not updated totalStrategyHoldings yet
		totalStrategyHoldings = updatedStratHoldings;
		uint256 underlyingFees = (profit * performanceFee) / 1e18;

		uint256 feeShares = toSharesAfterDeposit(underlyingFees);

		emit Harvest(treasury, profit, underlyingFees, feeShares, tvl);
		_mint(treasury, feeShares);
	}

	/// this can be done in parts in case gas limit is reached
	function depositIntoStrategies(DepositParams[] calldata params) public onlyRole(MANAGER) {
		for (uint256 i; i < params.length; i++) {
			DepositParams memory param = params[i];
			uint256 amountIn = param.amountIn;
			if (amountIn == 0) continue;
			ISCYStrategy strategy = param.strategy;
			if (!strategyExists[strategy]) revert StrategyNotFound();
			// update underlying float accouting
			beforeWithdraw(amountIn, 0);
			/// push funds to avoid approvals
			asset.safeTransfer(strategy.strategy(), amountIn);
			strategy.deposit(address(this), address(asset), 0, param.minSharesOut);
			totalStrategyHoldings += amountIn;
		}

		afterDeposit(0, 0);
	}

	/// this can be done in parts in case gas limit is reached
	function withdrawFromStrategies(RedeemParams[] calldata params) public onlyRole(MANAGER) {
		for (uint256 i; i < params.length; i++) {
			RedeemParams memory param = params[i];
			uint256 shares = param.shares;
			if (shares == 0) continue;
			ISCYStrategy strategy = param.strategy;
			if (!strategyExists[strategy]) revert StrategyNotFound();

			// no need to push share tokens - contract can burn them
			uint256 amountOut = strategy.redeem(
				address(this),
				shares,
				address(asset), // token out is allways asset
				param.minTokenOut
			);
			totalStrategyHoldings -= amountOut;
			// update underlying float accounting
			afterDeposit(amountOut, 0);
		}

		afterDeposit(0, 0);
	}

	/// gets accurate strategy holdings denominated in asset
	function _getStrategyHoldings() internal returns (uint256 tvl) {
		uint256 lastIndex = strategyIndex.length;
		/// TODO compute realistic limit for strategy array lengh to stay within gas limit
		for (uint256 i; i < lastIndex; i++) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.getUpdatedUnderlyingBalance(address(this));
		}
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

	/// returns expected tvl (used for estimate)
	function getTvl() public view returns (uint256 tvl) {
		uint256 length = strategyIndex.length;
		// there should be no untrusted strategies in this array
		for (uint256 i; i < length; i++) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.underlyingBalance(address(this));
		}
		tvl += asset.balanceOf(address(this));
	}

	function totalAssets() public view virtual override returns (uint256) {
		return floatAmnt + totalStrategyHoldings;
	}

	/// INTERFACE UTILS

	function underlyingBalance(address user) public view returns (uint256) {
		uint256 shares = balanceOf(user);
		return sharesToUnderlying(shares);
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

	function underlyingDecimals() public view returns (uint8) {
		return asset.decimals();
	}

	function underlying() public view returns (address) {
		return address(asset);
	}

	/*/////////////////////////////////////////////////////////
					CrossChain functionality
	/////////////////////////////////////////////////////////*/

	function finalizeDeposit() external onlyRole(MANAGER) {
		Message[] memory messages = postOffice.readMessage(messageType.DEPOSIT);

		// Doesn't check if the money was already there
		uint256 totalDeposited = 0;
		for (uint256 i = 0; i < messages.length; ) {
			// messages[i].value; messages[i].sender; messages[i].chainId;
			// Not sure about this safety check yet
			// // lock minimum liquidity if totalSupply is 0
			// if (totalSupply() == 0) {
			// 	if (MIN_LIQUIDITY > shares) revert MinLiquidity();
			// 	shares -= MIN_LIQUIDITY;
			// 	_mint(address(1), MIN_LIQUIDITY);
			// }

			uint256 shares = previewDeposit(messages[i].value);

			_mint(messages[i].sender, shares);

			unchecked {
				totalDeposited += messages[i].value;
				i++;
			}
		}

		// Should account for fees paid in tokens for using bridge
		// Also, if a value hasn't arrived manager will not be able to register any value
		if (totalDeposited > (asset.balanceOf(address(this)) - balanceBeforeCrossDeposit))
			revert MissingDepositValue();

		afterDeposit(0, 0);
		emit RegisterDeposit(totalDeposited);
	}

	function readWithdraw() external onlyRole(MANAGER) {
		Message[] memory messages = postOffice.readMessage(messageType.WITHDRAW);

		for (uint256 i = 0; i < messages.length; ) {
			// if (depositedVaults[messages[i].sender].amount != 0) revert PendingCrosschainWithdraw();
			if (depositedVaults[messages[i].sender].amount == 0) {
				bridgeQueue.push(messages[i].sender);
			}

			requestRedeem(messages[i].value, messages[i].sender);
			unchecked {
				depositedVaults[messages[i].sender].amount += messages[i].value;
				i++;
			}
		}
	}

	function finalizeWithdraw() external onlyRole(MANAGER) {
		uint256 length = bridgeQueue.length;

		uint256 total = 0;
		for (uint256 i = length; i > 0; ) {
			address vAddr = bridgeQueue[i - 1];

			depositedVaults[vAddr].amount = 0;
			bridgeQueue.pop();

			// MANAGER has to ensure that if bridge fails it will try again
			// OnChain record of needed bridge will be erased.
			emit BridgeAsset(
				chainId,
				depositedVaults[vAddr].chainId,
				depositedVaults[vAddr].amount
			);

			unchecked {
				total += depositedVaults[vAddr].amount;
				i--;
			}
		}

		beforeWithdraw(total, 0);
	}

	// This function should trigger harvest before sending back messages?
	function finalizeHarvest() external onlyRole(MANAGER) {
		// function finalizeHarvest(uint256 expectedTvl, uint256 maxDelta) external onlyRole(MANAGER) {
		// harvest(expectedTvl, maxDelta);

		Message[] memory messages = postOffice.readMessage(messageType.REQUESTHARVEST);

		uint256 sharePrice = withdrawSharePrice;
		for (uint256 i = 0; i < messages.length; ) {
			postOffice.sendMessage(
				messages[i].sender,
				Message(sharePrice, address(this), address(0), chainId),
				messages[i].chainId,
				messageType.HARVEST
			);

			unchecked {
				i++;
			}
		}
	}

	// Anyone can call emergencyWithdraw
	function finalizeEmergencyWithdraw() external {
		Message[] memory messages = postOffice.readMessage(messageType.EMERGENCYWITHDRAW);

		for (uint256 i = 0; i < messages.length; ) {
			uint256 transferShares = messages[i].value.mulWadDown(balanceOf(messages[i].sender));

			_transfer(messages[i].sender, messages[i].client, transferShares);
			emit EmergencyWithdraw(messages[i].sender, messages[i].client, transferShares);

			unchecked {
				i++;
			}
		}
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

	event RegisterDeposit(uint256 total);
	event EmergencyWithdraw(address vault, address client, uint256 shares);

	error NotEnoughtFloat();
	error WrongUnderlying();
	error SlippageExceeded();
	error StrategyExists();
	error StrategyNotFound();
	error MissingDepositValue();
}
