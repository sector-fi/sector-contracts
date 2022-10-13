// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { SectorVault } from "./SectorVault.sol";
import { ERC4626, FixedPointMathLib } from "./ERC4626/ERC4626.sol";
import { IPostOffice } from "../interfaces/postOffice/IPostOffice.sol";
import { XChainIntegrator } from "../common/XChainIntegrator.sol";
import { SectorBase } from "./SectorBase.sol";
import "../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

contract SectorCrossVault is SectorBase {
	using FixedPointMathLib for uint256;

	struct Request {
		address vaultAddr;
		uint256 amount;
	}

	struct HarvestLedger {
		uint256 localDepositValue;
		uint256 crossDepositValue;
		uint256 pendingAnswers;
		uint256 receivedAnswers;
	}

	// Used to harvest from deposited vaults
	address[] internal vaultList;
	// Harvest state
	HarvestLedger public harvestLedger;
	// Controls emergency withdraw
	// Not sure if this will be used
	bool internal emergencyEnabled = false;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee
	) ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;

			Vault memory vault = checkVault(vaultAddr);

			if (vault.chainId == chainId) {
				BatchedWithdraw(vaultAddr).deposit(amount, address(this));
			} else {
				_sendMessage(
					vaultAddr,
					vault,
					Message(amount, address(this), address(0), chainId),
					messageType.DEPOSIT
				);

				emit BridgeAsset(chainId, vault.chainId, amount);
			}

			unchecked {
				i++;
			}

			// update total holdings by child vaults
			totalChildHoldings += amount;
		}
	}

	function withdrawFromVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;

			Vault memory vault = checkVault(vaultAddr);

			if (vault.chainId == chainId) {
				BatchedWithdraw(vaultAddr).requestRedeem(amount);
			} else {
				_sendMessage(
					vaultAddr,
					vault,
					Message(amount, address(this), address(0), chainId),
					messageType.WITHDRAW
				);
			}

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
		// Still not sure about this part
		if (!emergencyEnabled) revert EmergencyNotEnabled();

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
		uint16 _srcPostmanId,
		uint16 _dstPostmanId,
		bool _allowed
	) external override onlyOwner {
		_addVault(_vault, _chainId, _srcPostmanId, _dstPostmanId, _allowed);
		vaultList.push(_vault);
	}

	function setMessageActionCallback() external override onlyOwner {
		messageAction[messageType.WITHDRAW] = _receiveWithdraw;
		messageAction[messageType.HARVEST] = _receiveHarvest;
	}

	/*/////////////////////////////////////////////////////
							Internals
	/////////////////////////////////////////////////////*/

	function checkVault(address _vault) internal view returns (Vault memory) {
		Vault memory vault = addrBook[_vault];
		if (!vault.allowed) revert VaultNotAllowed(_vault);
		return vault;
	}

	/// TODO: this method sholud be triggered by a chain vault when
	/// returning withdrawals. This allows us to upate floatAmnt and totalChildHoldings
	function _finalizedWithdraw() internal {
		uint256 totalWithdraw;
		totalChildHoldings -= totalWithdraw;
		afterDeposit(totalWithdraw, 0);
	}

	function _receiveWithdraw(Message calldata) internal {
		_finalizedWithdraw();
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
	error EmergencyNotEnabled();
	error MissingMessages();
}
