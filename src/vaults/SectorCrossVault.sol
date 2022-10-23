// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { SectorVault } from "./SectorVault.sol";
import { ERC4626, FixedPointMathLib, Fees, FeeConfig, Auth, AuthConfig } from "./ERC4626/ERC4626.sol";
import { IPostOffice } from "../interfaces/postOffice/IPostOffice.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import { SectorBase } from "./SectorBase.sol";
import "../interfaces/MsgStructs.sol";

import "hardhat/console.sol";

struct HarvestLedger {
	uint256 localDepositValue;
	uint256 crossDepositValue;
	uint256 pendingAnswers;
	uint256 receivedAnswers;
}

contract SectorCrossVault is SectorBase {
	using SafeERC20 for ERC20;
	using FixedPointMathLib for uint256;

	// Used to harvest from deposited vaults
	address[] internal vaultList;
	// Harvest state
	HarvestLedger public harvestLedger;
	Message[] internal withdrawQueue;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig
	) ERC4626(_asset, _name, _symbol) Auth(authConfig) Fees(feeConfig) BatchedWithdraw() {}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoXVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		uint256 totalAmount = 0;

		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;
			uint256 fee = vaults[i].fee;

			Vault memory vault = checkVault(vaultAddr);
			if (vault.chainId == chainId) revert SameChainOperation();

			totalAmount += amount;

			_sendMessage(
				vaultAddr,
				vault,
				Message(amount - fee, address(this), address(0), chainId),
				messageType.DEPOSIT
			);

			// This is fucked but dont know why
			_sendTokens(
				underlying(),
				vaults[i].allowanceTarget,
				vaults[i].registry,
				vaultAddr,
				amount,
				uint256(addrBook[vaultAddr].chainId),
				vaults[i].txData
			);

			emit BridgeAsset(chainId, vault.chainId, amount);

			unchecked {
				i++;
			}
		}

		beforeWithdraw(totalAmount, 0);
		totalChildHoldings += totalAmount;
	}

	function withdrawFromXVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;

			Vault memory vault = checkVault(vaultAddr);

			if (vault.chainId == chainId) revert SameChainOperation();

			_sendMessage(
				vaultAddr,
				vault,
				Message(amount, address(this), address(0), chainId),
				messageType.WITHDRAW
			);

			unchecked {
				i++;
			}
		}
	}

	function harvestVaults() public onlyRole(MANAGER) {
		uint256 localDepositValue = 0;

		if (harvestLedger.pendingAnswers != 0) revert OnGoingHarvest();

		uint256 vaultsLength = vaultList.length;
		uint256 xvaultsCount = 0;

		for (uint256 i = 0; i < vaultsLength; ) {
			address vaultAddr = vaultList[i];
			Vault memory vault = addrBook[vaultAddr];

			if (vault.chainId == chainId) {
				localDepositValue += SectorVault(vaultAddr).underlyingBalance(address(this));
			} else {
				_sendMessage(
					vaultAddr,
					vault,
					Message(0, address(this), address(0), chainId),
					messageType.HARVEST
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

	function emergencyWithdraw() external {
		uint256 userShares = balanceOf(msg.sender);

		_burn(msg.sender, userShares);
		uint256 userPerc = userShares.divWadDown(totalSupply());

		uint256 vaultsLength = vaultList.length;
		for (uint256 i = 0; i < vaultsLength; ) {
			address vaultAddr = vaultList[i];
			Vault memory vault = checkVault(vaultAddr);

			if (vault.chainId == chainId) {
				BatchedWithdraw _vault = BatchedWithdraw(vaultAddr);
				uint256 transferShares = userPerc.mulWadDown(_vault.balanceOf(address(this)));
				_vault.transfer(msg.sender, transferShares);
			} else {
				_sendMessage(
					vaultAddr,
					vault,
					Message(userPerc, address(this), msg.sender, chainId),
					messageType.EMERGENCYWITHDRAW
				);
			}

			unchecked {
				i++;
			}
		}
	}

	// Do linear search on vaultList -> O(n)
	function removeVault(address _vault) external onlyOwner {
		addrBook[_vault].allowed = false;

		uint256 length = vaultList.length;
		for (uint256 i = 0; i < length; ) {
			if (vaultList[i] == _vault) {
				vaultList[i] = vaultList[length - 1];
				vaultList.pop();

				emit ChangedVaultStatus(_vault, false);
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
		vaultList.push(_vault);
	}

	/*/////////////////////////////////////////////////////
							Internals
	/////////////////////////////////////////////////////*/

	function _handleMessage(messageType _type, Message calldata _msg) internal override {
		if (_type == messageType.WITHDRAW) _receiveWithdraw(_msg);
		else if (_type == messageType.HARVEST) _receiveHarvest(_msg);
		else revert NotImplemented();
	}

	function checkVault(address _vault) internal view returns (Vault memory) {
		Vault memory vault = addrBook[_vault];
		if (!vault.allowed) revert VaultNotAllowed(_vault);
		return vault;
	}

	function _receiveWithdraw(Message calldata _msg) internal {
		withdrawQueue.push(_msg);
	}

	function processIncomingXFunds() external override onlyRole(MANAGER) {
		uint256 length = withdrawQueue.length;
		uint256 total = 0;
		for (uint256 i = length; i > 0; ) {
			Message memory _msg = withdrawQueue[i - 1];
			withdrawQueue.pop();

			total += _msg.value;

			unchecked {
				i--;
			}
		}
		// Should account for fees paid in tokens for using bridge
		// Also, if a value hasn't arrived manager will not be able to register any value
		console.log(total);
		console.log(asset.balanceOf(address(this)));
		console.log(floatAmnt);
		console.log(pendingWithdraw);

		if (total < (asset.balanceOf(address(this)) - floatAmnt - pendingWithdraw))
			revert MissingIncomingXFunds();

		_finalizedWithdraw(total);
		emit RegisterIncomingFunds(total);
	}

	function _receiveHarvest(Message calldata _msg) internal {
		harvestLedger.crossDepositValue += _msg.value;
		harvestLedger.receivedAnswers += 1;
	}

	function _finalizedWithdraw(uint256 totalWithdraw) internal {
		// uint256 totalWithdraw;
		totalChildHoldings -= totalWithdraw;
		afterDeposit(totalWithdraw, 0);
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
