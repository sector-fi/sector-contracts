// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20, Fees, FeeConfig, Auth, AuthConfig } from "./ERC4626/ERC4626.sol";
import { ISCYStrategy } from "../interfaces/scy/ISCYStrategy.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";
import { SectorBase } from "./SectorBase.sol";

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

contract SectorVault is SectorBase {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;

	/// if vaults accepts native asset we set asset to address 0;
	address internal constant NATIVE = address(0);

	mapping(ISCYStrategy => bool) public strategyExists;
	address[] public strategyIndex;

	address[] bridgeQueue;

	constructor(
		ERC20 asset_,
		string memory _name,
		string memory _symbol,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		address _postOffice
	)
		ERC4626(asset_, _name, _symbol)
		Auth(authConfig)
		Fees(feeConfig)
		XChainIntegrator(_postOffice)
		BatchedWithdraw()
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
		for (uint256 i; i < length; ++i) {
			if (address(strategy) == strategyIndex[i]) {
				strategyIndex[i] = strategyIndex[length - 1];
				strategyIndex.pop();
				continue;
			}
		}
	}

	function totalStrategies() public view returns (uint256) {
		return strategyIndex.length;
	}

	/// We compute expected tvl off-chain first, to ensure this transactions isn't sandwitched
	function harvest(uint256 expectedTvl, uint256 maxDelta) public onlyRole(MANAGER) {
		uint256 currentChildHoldings = _getStrategyHoldings();
		uint256 tvl = currentChildHoldings + floatAmnt;
		_checkSlippage(expectedTvl, tvl, maxDelta);
		_harvest(currentChildHoldings);
	}

	/// this can be done in parts in case gas limit is reached
	function depositIntoStrategies(DepositParams[] calldata params) public onlyRole(MANAGER) {
		uint256 l = params.length;
		for (uint256 i; i < l; ++i) {
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
			totalChildHoldings += amountIn;
		}
	}

	/// this can be done in parts in case gas limit is reached
	function withdrawFromStrategies(RedeemParams[] calldata params) public onlyRole(MANAGER) {
		uint256 l = params.length;
		for (uint256 i; i < l; ++i) {
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
			totalChildHoldings -= amountOut;
			// update underlying float accounting
			afterDeposit(amountOut, 0);
		}
	}

	// this method ensures funds are redeemable if manager stops
	// processing harvests / withdrawals
	function emergencyRedeem() public {
		if (maxRedeemWindow > block.timestamp - lastHarvestTimestamp)
			revert NotEnoughTimeSinceHarvest();

		uint256 _totalSupply = totalSupply();
		uint256 shares = balanceOf(msg.sender);
		if (shares == 0) return;
		_burn(msg.sender, shares);

		// redeem proportional share of vault's underlying float balance
		uint256 underlyingShare = (floatAmnt * shares) / _totalSupply;
		beforeWithdraw(underlyingShare, 0);
		asset.safeTransfer(msg.sender, underlyingShare);

		uint256 l = strategyIndex.length;

		// redeem proportional share of each strategy
		for (uint256 i; i < l; ++i) {
			ERC20 stratToken = ERC20(strategyIndex[i]);
			uint256 balance = stratToken.balanceOf(address(this));
			uint256 userShares = (shares * balance) / _totalSupply;
			if (userShares == 0) continue;
			stratToken.safeTransfer(msg.sender, userShares);
		}
	}

	/// gets accurate strategy holdings denominated in asset
	function _getStrategyHoldings() internal returns (uint256 tvl) {
		uint256 l = strategyIndex.length;
		/// TODO compute realistic limit for strategy array lengh to stay within gas limit
		for (uint256 i; i < l; ++i) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.getUpdatedUnderlyingBalance(address(this));
		}
	}

	/// returns expected tvl (used for estimate)
	function getTvl() public view returns (uint256 tvl) {
		uint256 l = strategyIndex.length;
		// there should be no untrusted strategies in this array
		for (uint256 i; i < l; ++i) {
			ISCYStrategy strategy = ISCYStrategy(payable(strategyIndex[i]));
			tvl += strategy.underlyingBalance(address(this));
		}
		tvl += asset.balanceOf(address(this));
	}

	function totalAssets() public view virtual override returns (uint256) {
		return floatAmnt + totalChildHoldings;
	}

	/// INTERFACE UTILS

	/// @dev returns accurate value used to estimate current value
	function currentUnderlyingBalance(address user) external view returns (uint256) {
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

	/*/////////////////////////////////////////////////////////
					CrossChain functionality
	/////////////////////////////////////////////////////////*/

	/// TODO maybe common code to Sector Base
	function finalizeDeposit() external onlyRole(MANAGER) {
		Message[] memory messages = postOffice.readMessage(messageType.DEPOSIT);

		// Doesn't check if the money was already there
		uint256 totalDeposit = 0;
		uint256 l = messages.length;
		for (uint256 i = 0; i < l; ) {
			// messages[i].value; messages[i].sender; messages[i].chainId;

			uint256 shares = previewDeposit(messages[i].value);

			// lock minimum liquidity if totalSupply is 0
			// if i > 0 we can skip this
			if (i == 0 && totalSupply() == 0) {
				if (MIN_LIQUIDITY > shares) revert MinLiquidity();
				shares -= MIN_LIQUIDITY;
				_mint(address(1), MIN_LIQUIDITY);
			}

			_mint(messages[i].sender, shares);

			unchecked {
				totalDeposit += messages[i].value;
				i++;
			}
		}

		// Should account for fees paid in tokens for using bridge
		// Also, if a value hasn't arrived manager will not be able to register any value
		if (totalDeposit > (asset.balanceOf(address(this)) - floatAmnt - pendingWithdraw))
			revert MissingDepositValue();

		// update floatAmnt with deposited funds
		afterDeposit(totalDeposit, 0);
		/// TODO should we add more params here?
		emit RegisterDeposit(totalDeposit);
	}

	/// This can be triggered directly
	function readWithdraw() external onlyRole(MANAGER) {
		Message[] memory messages = postOffice.readMessage(messageType.WITHDRAW);

		uint256 l = messages.length;
		for (uint256 i = 0; i < l; ) {
			// if (depositedVaults[messages[i].sender].amount != 0) revert PendingCrosschainWithdraw();
			if (depositedVaults[messages[i].sender].amount == 0) {
				bridgeQueue.push(messages[i].sender);
			}
			/// value here is the fraction of the shares owned by the vault
			/// since the xVault doesn't know how many shares it holds
			uint256 xVaultShares = balanceOf(messages[i].sender);
			uint256 shares = (messages[i].value * xVaultShares) / 1e18;
			requestRedeem(shares, messages[i].sender);

			// TODO Do we need this for anything other than the check above?
			// is there a better way to filter out sequential withdraw req?
			// a bool field?
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

			// this returns the underlying amount the vault is withdrawing
			uint256 amountOut = _xRedeem(vAddr);

			bridgeQueue.pop();

			// MANAGER has to ensure that if bridge fails it will try again
			// OnChain record of needed bridge will be erased.
			emit BridgeAsset(chainId, depositedVaults[vAddr].chainId, amountOut);

			unchecked {
				total += amountOut;
				i--;
			}
		}

		beforeWithdraw(total, 0);
	}

	// This function should trigger harvest before sending back messages?
	// This method should be safe to trigger directly in response to
	// REQUESTHARVEST - this means we don't need to use the read message queue but trigger it directlys
	function finalizeHarvest() external onlyRole(MANAGER) {
		// function finalizeHarvest(uint256 expectedTvl, uint256 maxDelta) external onlyRole(MANAGER) {
		// harvest(expectedTvl, maxDelta);

		Message[] memory messages = postOffice.readMessage(messageType.REQUESTHARVEST);

		uint256 l = messages.length;
		for (uint256 i = 0; i < l; ) {
			// this message should respond with underlying value
			// because XVault doesn't know how many shares it holds
			uint256 xVaultUnderlyingBalance = underlyingBalance(messages[i].sender);
			postOffice.sendMessage(
				messages[i].sender,
				Message(xVaultUnderlyingBalance, address(this), address(0), chainId),
				messages[i].chainId,
				messageType.HARVEST
			);

			unchecked {
				i++;
			}
		}
	}

	// Anyone can call emergencyWithdraw
	// TODO trigger this method directly on message arrival?
	function finalizeEmergencyWithdraw() external {
		Message[] memory messages = postOffice.readMessage(messageType.EMERGENCYWITHDRAW);

		uint256 l = messages.length;
		for (uint256 i = 0; i < l; ) {
			uint256 transferShares = messages[i].value.mulWadDown(balanceOf(messages[i].sender));

			_transfer(messages[i].sender, messages[i].client, transferShares);
			emit EmergencyWithdraw(messages[i].sender, messages[i].client, transferShares);

			unchecked {
				i++;
			}
		}
	}
}
