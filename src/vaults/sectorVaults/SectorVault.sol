// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20, Fees, FeeConfig, Auth, AuthConfig } from "../ERC4626/ERC4626.sol";
import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
import { SectorBase } from "../ERC4626/SectorBase.sol";
import { BatchedWithdraw } from "../ERC4626/BatchedWithdraw.sol";
import { XChainIntegrator } from "../../xChain/XChainIntegrator.sol";
import "../../interfaces/MsgStructs.sol";

import "hardhat/console.sol";
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

contract SectorVault is SectorBase, XChainIntegrator {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;

	/// if vaults accepts native asset we set asset to address 0;
	address internal constant NATIVE = address(0);

	mapping(ISCYStrategy => bool) public strategyExists;
	address[] public strategyIndex;
	VaultAddr[] public bridgeQueue;

	uint256 public totalStrategyHoldings;

	constructor(
		ERC20 asset_,
		string memory _name,
		string memory _symbol,
		bool _useNativeAsset,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		uint256 _maxBridgeFeeAllowed
	)
		ERC4626(asset_, _name, _symbol, _useNativeAsset)
		Auth(authConfig)
		Fees(feeConfig)
		BatchedWithdraw()
		XChainIntegrator(_maxBridgeFeeAllowed)
	{}

	function addStrategy(ISCYStrategy strategy) public onlyOwner {
		if (strategyExists[strategy]) revert StrategyExists();

		/// make sure underlying matches
		if (address(strategy.underlying()) != address(asset)) revert WrongUnderlying();

		strategyExists[strategy] = true;
		strategyIndex.push(address(strategy));
		emit AddStrategy(address(strategy));
	}

	function removeStrategy(ISCYStrategy strategy) public onlyOwner {
		if (!strategyExists[strategy]) revert StrategyNotFound();
		strategyExists[strategy] = false;
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
			ISCYStrategy strategy = param.strategy;
			if (!strategyExists[strategy]) revert StrategyNotFound();
			// update underlying float accouting
			beforeWithdraw(amountIn, 0);
			/// push funds to avoid approvals
			asset.safeTransfer(strategy.strategy(), amountIn);
			strategy.deposit(address(this), address(asset), 0, param.minSharesOut);
			totalChildHoldings += amountIn;
			emit DepositIntoStrategy(msg.sender, address(strategy), amountIn);
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
			emit WithdrawFromStrategy(msg.sender, address(strategy), amountOut);
		}
	}

	function emergencyRedeem() public {
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

	/*/////////////////////////////////////////////////////////
					CrossChain functionality
	/////////////////////////////////////////////////////////*/

	function _handleMessage(MessageType _type, Message calldata _msg) internal override {
		if (_type == MessageType.DEPOSIT) _receiveDeposit(_msg);
		else if (_type == MessageType.HARVEST) _receiveHarvest(_msg);
		else if (_type == MessageType.WITHDRAW) _receiveWithdraw(_msg);
		else if (_type == MessageType.EMERGENCYWITHDRAW) _receiveEmergencyWithdraw(_msg);
		else revert NotImplemented();
	}

	function _receiveDeposit(Message calldata _msg) internal {
		incomingQueue.push(_msg);
	}

	function _receiveWithdraw(Message calldata _msg) internal {
		address xVaultAddr = getXAddr(_msg.sender, _msg.chainId);

		if (withdrawLedger[xVaultAddr].value == 0)
			bridgeQueue.push(VaultAddr(_msg.sender, _msg.chainId));

		/// value here is the fraction of the shares owned by the vault
		/// since the xVault doesn't know how many shares it holds
		uint256 xVaultShares = balanceOf(xVaultAddr);
		uint256 shares = (_msg.value * xVaultShares) / 1e18;
		_requestRedeem(shares, xVaultAddr, xVaultAddr);
	}

	function _receiveEmergencyWithdraw(Message calldata _msg) internal {
		address xVaultAddr = getXAddr(_msg.sender, _msg.chainId);

		uint256 transferShares = (_msg.value * balanceOf(xVaultAddr)) / 1e18;

		_transfer(xVaultAddr, _msg.client, transferShares);
		emit EmergencyWithdraw(_msg.sender, _msg.client, transferShares);
	}

	// TODO should it trigger harvest first?
	function _receiveHarvest(Message calldata _msg) internal {
		address xVaultAddr = getXAddr(_msg.sender, _msg.chainId);

		uint256 xVaultUnderlyingBalance = underlyingBalance(xVaultAddr);

		Vault memory vault = addrBook[xVaultAddr];
		_sendMessage(
			_msg.sender,
			_msg.chainId,
			vault,
			Message(xVaultUnderlyingBalance, address(this), address(0), chainId),
			MessageType.HARVEST
		);
	}

	function processIncomingXFunds() external override onlyRole(MANAGER) {
		uint256 length = incomingQueue.length;
		uint256 totalDeposit = 0;
		for (uint256 i = length; i > 0; ) {
			Message memory _msg = incomingQueue[i - 1];
			incomingQueue.pop();

			uint256 shares = previewDeposit(_msg.value);
			// lock minimum liquidity if totalSupply is 0
			// if i > 0 we can skip this
			if (i == 0 && totalSupply() == 0) {
				if (MIN_LIQUIDITY > shares) revert MinLiquidity();
				shares -= MIN_LIQUIDITY;
				_mint(address(1), MIN_LIQUIDITY);
			}
			_mint(getXAddr(_msg.sender, _msg.chainId), shares);

			unchecked {
				totalDeposit += _msg.value;
				i--;
			}
		}
		// Should account for fees paid in tokens for using bridge
		// Also, if a value hasn't arrived manager will not be able to register any value

		uint256 pendingWithdraw = convertToAssets(pendingRedeem);
		if (totalDeposit > (asset.balanceOf(address(this)) - floatAmnt - pendingWithdraw))
			revert MissingIncomingXFunds();

		// update floatAmnt with deposited funds
		afterDeposit(totalDeposit, 0);
		/// TODO should we add more params here?
		emit RegisterIncomingFunds(totalDeposit);
	}

	// Problem -> bridgeQueue has an order and request array has to follow this order
	// Maybe change how withdraws are saved?
	function processXWithdraw(Request[] calldata requests) external payable onlyRole(MANAGER) {
		uint256 length = bridgeQueue.length;

		for (uint256 i = length; i > 0; ) {
			VaultAddr memory v = bridgeQueue[i - 1];

			if (requests[i - 1].vaultAddr != v.addr) revert VaultAddressNotMatch();
			address xVaultAddr = getXAddr(v.addr, v.chainId);

			// this returns the underlying amount the vault is withdrawing
			uint256 amountOut = _xRedeem(xVaultAddr, v.addr);
			checkBridgeFee(amountOut, requests[i - 1].bridgeFee);
			bridgeQueue.pop();

			_sendMessage(
				v.addr,
				v.chainId,
				addrBook[xVaultAddr],
				Message(amountOut - requests[i - 1].bridgeFee, address(this), address(0), chainId),
				MessageType.WITHDRAW
			);

			_sendTokens(
				underlying(),
				requests[i - 1].allowanceTarget,
				requests[i - 1].registry,
				v.addr,
				amountOut,
				v.chainId,
				requests[i - 1].txData
			);

			emit BridgeAsset(chainId, v.chainId, amountOut);

			unchecked {
				i--;
			}
		}
	}

	error VaultAddressNotMatch();
	event AddStrategy(address indexed strategy);
	event RemoveStrategy(address indexed strategy);
	event DepositIntoStrategy(address caller, address strategy, uint256 amount);
	event WithdrawFromStrategy(address caller, address strategy, uint256 amount);
}
