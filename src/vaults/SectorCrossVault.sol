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
		uint256 count;
	}

	// TODO Implement functions with harvestLock modifier

	// Harvest state
	HarvestLedger public harvestLedger;
	// Controls emergency withdraw
	bool internal emergencyEnabled = false;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee,
		address postOffice
	)
		ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee)
		XChainIntegrator(postOffice)
		BatchedWithdraw()
	{}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;
			Vault memory tmpVault = depositedVaults[vaultAddr];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaultAddr);

			if (tmpVault.chainId == chainId) {
				BatchedWithdraw(vaultAddr).deposit(amount, address(this));
			} else {
				postOffice.sendMessage(
					vaultAddr,
					Message(amount, address(this), address(0), chainId),
					tmpVault.chainId,
					messageType.DEPOSIT
				);

				emit BridgeAsset(uint16(block.chainid), tmpVault.chainId, amount);
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
			Vault memory tmpVault = depositedVaults[vaultAddr];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaultAddr);

			if (tmpVault.chainId == chainId) {
				BatchedWithdraw(vaultAddr).requestRedeem(amount);
			} else {
				postOffice.sendMessage(
					vaultAddr,
					Message(amount, address(this), address(0), chainId),
					tmpVault.chainId,
					messageType.WITHDRAW
				);
			}

			unchecked {
				i++;
			}
		}
	}

	/// TODO: this method sholud be triggered by a chain vault when
	/// returning withdrawals. This allows us to upate floatAmnt and totalChildHoldings
	function _finalizedWithdraw() internal {
		uint256 totalWithdraw;
		totalChildHoldings -= totalWithdraw;
		afterDeposit(totalWithdraw, 0);
	}

	function harvestVaults() public onlyRole(MANAGER) {
		uint256 localDepositValue = 0;

		if (harvestLedger.count != 0) revert OnGoingHarvest();

		uint256 vaultsLength = vaultList.length;
		uint256 xvaultsCount = 0;

		for (uint256 i = 0; i < vaultsLength; ) {
			address vAddr = vaultList[i];
			Vault memory tmpVault = depositedVaults[vAddr];

			if (tmpVault.chainId == chainId) {
				localDepositValue += SectorVault(vAddr).underlyingBalance(address(this));
			} else {
				postOffice.sendMessage(
					vAddr,
					Message(0, address(this), address(0), chainId),
					tmpVault.chainId,
					messageType.REQUESTHARVEST
				);
				xvaultsCount += 1;
			}

			unchecked {
				i++;
			}
		}

		harvestLedger.localDepositValue = localDepositValue;
		harvestLedger.count = xvaultsCount;
	}

	function finalizeHarvest(uint256 expectedValue, uint256 maxDelta) public onlyRole(MANAGER) {
		HarvestLedger storage ledger = harvestLedger;
		uint256 ledgerCount = ledger.count;

		if (ledgerCount == 0) revert HarvestNotOpen();

		// Compute actual tvl
		(uint256 xDepositValue, uint256 count) = postOffice.readMessageSumReduce(
			messageType.HARVEST
		);

		// The only save check besides computed tvl now is the number o messages.
		if (ledgerCount > count) revert MissingMessages();

		uint256 currentChildHoldings = ledger.localDepositValue + xDepositValue;

		// TODO should expectedValue include balance?
		// uint256 tvl = currentChildHoldings + asset.balanceOf(address(this));
		_checkSlippage(expectedValue, currentChildHoldings, maxDelta);
		_harvest(currentChildHoldings);

		// Change harvest status
		ledger.localDepositValue = 0;
		ledger.count = 0;
	}

	function emergencyWithdraw() external {
		// Still not sure about this part
		if (!emergencyEnabled) revert EmergencyNotEnabled();

		uint256 userShares = balanceOf(msg.sender);

		_burn(msg.sender, userShares);
		uint256 userPerc = userShares.divWadDown(totalSupply());

		uint256 vaultsLength = vaultList.length;
		for (uint256 i = 0; i < vaultsLength; ) {
			address vAddr = vaultList[i];
			Vault memory tmpVault = depositedVaults[vAddr];

			if (tmpVault.chainId == chainId) {
				BatchedWithdraw vault = BatchedWithdraw(vAddr);
				uint256 transferShares = userPerc.mulWadDown(vault.balanceOf(address(this)));
				vault.transfer(msg.sender, transferShares);
			} else {
				postOffice.sendMessage(
					vAddr,
					Message(userPerc, address(this), msg.sender, chainId),
					tmpVault.chainId,
					messageType.EMERGENCYWITHDRAW
				);
			}

			unchecked {
				i++;
			}
		}
	}

	/*/////////////////////////////////////////////////////
						Modifiers
	/////////////////////////////////////////////////////*/

	modifier harvestLock() {
		if (harvestLedger.count != 0) revert OnGoingHarvest();
		_;
	}

	/*/////////////////////////////////////////////////////
							Errors
	/////////////////////////////////////////////////////*/

	error HarvestNotOpen();
	error OnGoingHarvest();
	error EmergencyNotEnabled();
	error MissingMessages();
}
