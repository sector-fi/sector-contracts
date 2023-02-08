// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib, SafeERC20, Fees, FeeConfig, Auth, AuthConfig } from "../ERC4626/ERC4626.sol";
import { SectorBase } from "../ERC4626/SectorBase.sol";
import { XChainIntegrator } from "../../xChain/XChainIntegrator.sol";
import { Message, VaultAddr, MessageType, Request, Vault } from "../../interfaces/MsgStructs.sol";
import { AggregatorVault, DepositParams, RedeemParams } from "./AggregatorVault.sol";

// import "hardhat/console.sol";

contract SectorVault is AggregatorVault, XChainIntegrator {
	using FixedPointMathLib for uint256;
	using SafeERC20 for ERC20;
	VaultAddr[] public bridgeQueue;
	Message[] internal depositQueue;

	constructor(
		ERC20 asset_,
		string memory _name,
		string memory _symbol,
		bool _useNativeAsset,
		uint256 _maxHarvestInterval,
		uint256 _maxTvl,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		uint256 _maxBridgeFeeAllowed
	)
		AggregatorVault(
			asset_,
			_name,
			_symbol,
			_useNativeAsset,
			_maxHarvestInterval,
			_maxTvl,
			authConfig,
			feeConfig
		)
		XChainIntegrator(_maxBridgeFeeAllowed)
	{}

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

	/// @dev should only be called by manager on behalf of xVaults
	function _xRedeem(address xVault, address _vault) internal returns (uint256 amountOut) {
		uint256 shares;
		(amountOut, shares) = _redeem(xVault);
		emit Withdraw(_vault, _vault, _vault, amountOut, shares);
	}

	error VaultAddressNotMatch();
}
