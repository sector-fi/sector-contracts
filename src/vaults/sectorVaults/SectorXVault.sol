// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SectorVault } from "./SectorVault.sol";
import { ERC4626, FixedPointMathLib, Fees, FeeConfig, Auth, AuthConfig } from "../ERC4626/ERC4626.sol";
import { SectorBase } from "../ERC4626/SectorBase.sol";
import { BatchedWithdraw } from "../ERC4626/BatchedWithdraw.sol";
import { XChainIntegrator } from "../../xChain/XChainIntegrator.sol";
import "../../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

struct HarvestLedger {
	uint256 localDepositValue;
	uint256 crossDepositValue;
	uint256 pendingAnswers;
	uint256 receivedAnswers;
}

contract SectorXVault is SectorBase, XChainIntegrator {
	using SafeERC20 for ERC20;
	using FixedPointMathLib for uint256;

	// Used to harvest from deposited vaults
	VaultAddr[] public vaultList;
	// Harvest state
	HarvestLedger public harvestLedger;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		bool _useNativeAsset,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		uint256 _maxBridgeFeeAllowed
	)
		ERC4626(_asset, _name, _symbol, _useNativeAsset)
		Auth(authConfig)
		Fees(feeConfig)
		BatchedWithdraw()
		XChainIntegrator(_maxBridgeFeeAllowed)
	{}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoXVaults(Request[] calldata vaults) public payable onlyRole(MANAGER) {
		uint256 totalAmount = 0;

		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint16 vaultChainId = vaults[i].vaultChainId;
			uint256 amount = vaults[i].amount;

			checkBridgeFee(amount, vaults[i].bridgeFee);

			if (vaultChainId == chainId) revert SameChainOperation();
			Vault memory vault = checkVault(vaultAddr, vaultChainId);

			totalAmount += amount;

			// TODO make a fee validation HERE
			_sendMessage(
				vaultAddr,
				vaultChainId,
				vault,
				Message(amount - vaults[i].bridgeFee, address(this), address(0), chainId),
				MessageType.DEPOSIT
			);

			_sendTokens(
				underlying(),
				vaults[i].allowanceTarget,
				vaults[i].registry,
				vaultAddr,
				amount,
				uint256(vaultChainId),
				vaults[i].txData
			);

			emit BridgeAsset(chainId, vaultChainId, amount);

			unchecked {
				i++;
			}
		}

		beforeWithdraw(totalAmount, 0);
		totalChildHoldings += totalAmount;
	}

	// TODO params should be just vault and amnt
	function withdrawFromXVaults(Request[] calldata vaults) public payable onlyRole(MANAGER) {
		// withdrawing from xVaults should not happen during harvest
		// this will mess up accounting
		if (harvestLedger.pendingAnswers != 0) revert OnGoingHarvest();

		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint16 vaultChainId = vaults[i].vaultChainId;
			uint256 amount = vaults[i].amount;

			if (vaultChainId == chainId) revert SameChainOperation();

			Vault memory vault = checkVault(vaultAddr, vaultChainId);

			_sendMessage(
				vaultAddr,
				vaultChainId,
				vault,
				Message(amount, address(this), address(0), chainId),
				MessageType.WITHDRAW
			);

			unchecked {
				i++;
			}
		}
	}

	function harvestVaults() public payable onlyRole(MANAGER) {
		uint256 localDepositValue = 0;

		if (harvestLedger.pendingAnswers != 0) revert OnGoingHarvest();

		uint256 vaultsLength = vaultList.length;
		uint256 xvaultsCount = 0;

		for (uint256 i = 0; i < vaultsLength; ) {
			VaultAddr memory v = vaultList[i];

			if (v.chainId == chainId) {
				localDepositValue += SectorVault(payable(v.addr)).underlyingBalance(address(this));
			} else {
				Vault memory vault = addrBook[getXAddr(v.addr, v.chainId)];

				_sendMessage(
					v.addr,
					v.chainId,
					vault,
					Message(0, address(this), address(0), chainId),
					MessageType.HARVEST
				);

				unchecked {
					xvaultsCount += 1;
				}
			}

			unchecked {
				i++;
			}
		}

		harvestLedger = HarvestLedger(localDepositValue, 0, xvaultsCount, 0);
	}

	function finalizeHarvest(uint256 expectedValue, uint256 maxDelta) public onlyRole(MANAGER) {
		HarvestLedger memory ledger = harvestLedger;

		if (ledger.pendingAnswers == 0) revert HarvestNotOpen();
		if (ledger.receivedAnswers < ledger.pendingAnswers) revert MissingMessages();

		uint256 currentChildHoldings = ledger.localDepositValue + ledger.crossDepositValue;

		// TODO should expectedValue include balance?
		// uint256 tvl = currentChildHoldings + asset.balanceOf(address(this));
		_checkSlippage(expectedValue, currentChildHoldings, maxDelta);
		_harvest(currentChildHoldings);

		// Change harvest status
		harvestLedger = HarvestLedger(0, 0, 0, 0);
	}

	function emergencyWithdraw() external payable {
		uint256 userShares = balanceOf(msg.sender);

		_burn(msg.sender, userShares);
		uint256 userPerc = userShares.divWadDown(totalSupply());

		uint256 vaultsLength = vaultList.length;
		for (uint256 i = 0; i < vaultsLength; ) {
			VaultAddr memory v = vaultList[i];
			Vault memory vault = checkVault(v.addr, v.chainId);

			if (v.chainId == chainId) {
				BatchedWithdraw _vault = BatchedWithdraw(payable(v.addr));
				uint256 transferShares = userPerc.mulWadDown(_vault.balanceOf(address(this)));
				_vault.transfer(msg.sender, transferShares);
			} else {
				_sendMessage(
					v.addr,
					v.chainId,
					vault,
					Message(userPerc, address(this), msg.sender, chainId),
					MessageType.EMERGENCYWITHDRAW
				);
			}

			unchecked {
				i++;
			}
		}
	}

	// Do linear search on vaultList -> O(n)
	function removeVault(address _vault, uint16 _chainId) external onlyOwner {
		addrBook[getXAddr(_vault, _chainId)].allowed = false;

		uint256 length = vaultList.length;
		for (uint256 i = 0; i < length; ) {
			VaultAddr memory v = vaultList[i];

			if (v.addr == _vault && v.chainId == _chainId) {
				vaultList[i] = vaultList[length - 1];
				vaultList.pop();

				emit ChangedVaultStatus(_vault, _chainId, false);
				return;
			}
			unchecked {
				i++;
			}
		}
	}

	/*/////////////////////////////////////////////////////
							Overrides
	/////////////////////////////////////////////////////*/

	function addVault(
		address _vault,
		uint16 _chainId,
		uint16 _postmanId,
		bool _allowed
	) external override onlyOwner {
		_addVault(_vault, _chainId, _postmanId, _allowed);
		vaultList.push(VaultAddr(_vault, _chainId));
	}

	/*/////////////////////////////////////////////////////
							Internals
	/////////////////////////////////////////////////////*/

	function _handleMessage(MessageType _type, Message calldata _msg) internal override {
		if (_type == MessageType.WITHDRAW) _receiveWithdraw(_msg);
		else if (_type == MessageType.HARVEST) _receiveHarvest(_msg);
		else revert NotImplemented();
	}

	function checkVault(address _vault, uint16 _chainId) internal returns (Vault memory) {
		Vault memory vault = addrBook[getXAddr(_vault, _chainId)];
		if (!vault.allowed) revert VaultNotAllowed(_vault, _chainId);
		return vault;
	}

	function _receiveWithdraw(Message calldata _msg) internal {
		incomingQueue.push(_msg);
	}

	function processIncomingXFunds() external override onlyRole(MANAGER) {
		uint256 length = incomingQueue.length;
		uint256 total = 0;
		for (uint256 i = length; i > 0; ) {
			Message memory _msg = incomingQueue[i - 1];
			incomingQueue.pop();

			total += _msg.value;

			unchecked {
				i--;
			}
		}
		// Should account for fees paid in tokens for using bridge
		// Also, if a value hasn't arrived manager will not be able to register any value
		uint256 pendingWithdraw = convertToAssets(pendingRedeem);
		if (total < (asset.balanceOf(address(this)) - floatAmnt - pendingWithdraw))
			revert MissingIncomingXFunds();

		totalChildHoldings -= total;
		afterDeposit(total, 0);
		emit RegisterIncomingFunds(total);
	}

	function _receiveHarvest(Message calldata _msg) internal {
		harvestLedger.crossDepositValue += _msg.value;
		harvestLedger.receivedAnswers += 1;
	}

	/*/////////////////////////////////////////////////////
							Modifiers
	/////////////////////////////////////////////////////*/

	// modifier harvestLock() {
	// 	if (harvestLedger.count != 0) revert OnGoingHarvest();
	// 	_;
	// }

	/*/////////////////////////////////////////////////////
							Errors
	/////////////////////////////////////////////////////*/

	error HarvestNotOpen();
	error OnGoingHarvest();
	error MissingMessages();
}
