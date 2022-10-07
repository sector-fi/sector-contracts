// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { ERC4626, FixedPointMathLib } from "./ERC4626/ERC4626.sol";
import { IXAdapter } from "../interfaces/adapters/IXAdapter.sol";
import { SocketIntegrator } from "../common/SocketIntegrator.sol";

// import "hardhat/console.sol";

contract SectorCrossVault is BatchedWithdraw, SocketIntegrator {
	using FixedPointMathLib for uint256;

	enum msgType {
		NONE,
		DEPOSIT,
		REDEEM,
		REQUESTREDEEM,
		REQUESTVALUEOFSHARES,
		EMERGENCYWITHDRAW
	}

	struct Vault {
		uint16 chainId;
		address adapter;
		bool allowed;
	}

	struct Request {
		address vaultAddr;
		uint256 amount;
	}

	struct HarvestRequest {
		uint256 timestamp;
		uint256 chainId;
		address vault;
	}

	struct HarvestLedger {
		uint256 localDepositValue;
		bool isOpen;
		uint256 openIndex;
		HarvestRequest[] request;
	}

	// TODO Implement functions with harvestLock modifier

	// Controls deposits
	mapping(address => Vault) public depositedVaults;
	address[] internal vaultsArr;

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
		uint256 _perforamanceFee
	) ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;
			Vault memory tmpVault = depositedVaults[vaultAddr];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaultAddr);

			if (tmpVault.adapter == address(0)) {
				BatchedWithdraw(vaultAddr).deposit(amount, address(this));
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					amount,
					vaultAddr,
					address(this),
					tmpVault.chainId,
					uint16(msgType.DEPOSIT),
					uint16(block.chainid)
				);

				emit BridgeAsset(uint16(block.chainid), tmpVault.chainId, amount);
			}

			unchecked {
				i++;
			}
		}
	}

	function withdrawFromVaults(Request[] calldata vaults) public onlyRole(MANAGER) {
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint256 amount = vaults[i].amount;
			Vault memory tmpVault = depositedVaults[vaultAddr];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaultAddr);

			if (tmpVault.adapter == address(0)) {
				BatchedWithdraw(vaultAddr).requestRedeem(amount);
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					amount,
					vaultAddr,
					address(this),
					tmpVault.chainId,
					uint16(msgType.REQUESTREDEEM),
					uint16(block.chainid)
				);
			}

			unchecked {
				i++;
			}
		}
	}

	// function redeemFromVaults(address[] calldata vaults, uint256[] calldata shares)
	// 	public
	// 	onlyRole(MANAGER)
	// 	checkInputSize(vaults.length, shares.length)
	// {
	// 	for (uint256 i = 0; i < vaults.length; ) {
	// 		Vault memory tmpVault = depositedVaults[vaults[i]];

	// 		if (tmpVault.allowed) revert VaultNotAllowed(vaults[i]);

	// 		if (tmpVault.adapter == address(0)) {
	// 			BatchedWithdraw(vaults[i]).redeem(shares[i], address(this), address(this));
	// 		} else {
	// 			IXAdapter(tmpVault.adapter).sendMessage(
	// 				shares[i],
	// 				vaults[i],
	// 				address(this),
	// 				tmpVault.chainId,
	// 				uint16(msgType.REDEEM),
	// 				uint16(block.chainid)
	// 			);
	// 		}
	// 		// Not sure if it should request manager intervention after redeem when in different chains

	// 		unchecked {
	// 			i++;
	// 		}
	// 	}
	// }

	// Not sure if caller has to pass array of vaults
	// Can be dangerous if manager fails or forgets an address
	// TODO asks loaner
	function harvestVaults() public onlyRole(MANAGER) {
		uint256 localDepositValue = 0;

		if (harvestLedger.isOpen) revert OnGoingHarvest();

		// uint256 length = vaultsArr.length;
		address[] memory vArr = vaultsArr;

		for (uint256 i = 0; i < vArr.length; ) {
			Vault memory tmpVault = depositedVaults[vArr[i]];

			if (tmpVault.adapter == address(0)) {
				localDepositValue +=
					BatchedWithdraw(vArr[i]).balanceOf(address(this)) *
					BatchedWithdraw(vArr[i]).withdrawSharePrice();
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					0,
					vArr[i],
					address(this),
					tmpVault.chainId,
					uint16(msgType.REQUESTVALUEOFSHARES),
					uint16(block.chainid)
				);

				harvestLedger.request.push(
					HarvestRequest(block.timestamp, tmpVault.chainId, vArr[i])
				);
			}
			unchecked {
				i++;
			}
		}

		harvestLedger.localDepositValue = localDepositValue;
		harvestLedger.isOpen = true;
	}

	function finalizeHarvest(uint256 expectedValue, uint256 maxDelta) public onlyRole(MANAGER) {
		HarvestLedger memory hLedger = harvestLedger;

		// Compute actual tvl
		uint256 xDepositValue = 0;

		if (!hLedger.isOpen) revert HarvestNotOpen();

		// Get all values from message board
		uint256 i = hLedger.openIndex;
		while (i < hLedger.request.length) {
			Vault memory tmpVault = depositedVaults[hLedger.request[i].vault];

			// If timestamp > message.timestamp transaction will revert
			uint256 value = IXAdapter(tmpVault.adapter).readMessage(
				hLedger.request[i].vault,
				tmpVault.chainId,
				hLedger.request[i].timestamp
			);
			xDepositValue += value;

			unchecked {
				i++;
			}
		}

		// Check if tvl is expected before commiting
		uint256 delta = expectedValue > xDepositValue
			? expectedValue - xDepositValue
			: xDepositValue - expectedValue;
		if (delta > maxDelta) revert SlippageExceeded();

		// Commit values
		_processWithdraw((hLedger.localDepositValue + xDepositValue) / totalSupply());

		// Change harvest status
		harvestLedger.openIndex = i;
		harvestLedger.localDepositValue = 0;
		harvestLedger.isOpen = false;
	}

	function emergencyWithdraw() external {
		if (!emergencyEnabled) revert EmergencyNotEnabled();

		uint256 userShares = balanceOf(msg.sender);

		_burn(msg.sender, userShares);
		uint256 userPerc = userShares.divWadDown(totalSupply());

		for (uint256 i = 0; i < vaultsArr.length; ) {
			Vault memory tmpVault = depositedVaults[vaultsArr[i]];
			BatchedWithdraw vault = BatchedWithdraw(vaultsArr[i]);

			uint256 transferShares = userPerc.mulWadDown(vault.balanceOf(address(this)));

			if (tmpVault.adapter == address(0)) {
				vault.transfer(msg.sender, transferShares);
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					transferShares,
					vaultsArr[i],
					address(this),
					tmpVault.chainId,
					uint16(msgType.EMERGENCYWITHDRAW),
					uint16(block.chainid)
				);
			}

			unchecked {
				i++;
			}
		}
	}

	/*/////////////////////////////////////////////////////
					Vault Management
	/////////////////////////////////////////////////////*/

	// Add to array of addresses
	function addVault(
		address vault,
		uint16 chainId,
		address adapter,
		bool allowed
	) external onlyOwner {
		Vault memory tmpVault = depositedVaults[vault];

		if (tmpVault.chainId != 0 || tmpVault.adapter != address(0) || tmpVault.allowed != false)
			revert VaultAlreadyAdded();

		depositedVaults[vault] = Vault(chainId, adapter, allowed);
		vaultsArr.push(vault);
		emit AddVault(vault, chainId, adapter);
	}

	function updateVaultAdapter(address vault, address adapter) external onlyOwner {
		depositedVaults[vault].adapter = adapter;

		emit UpdateVaultAdapter(vault, adapter);
	}

	function changeVaultStatus(address vault, bool allowed) external onlyOwner {
		depositedVaults[vault].allowed = allowed;

		emit ChangeVaultStatus(vault, allowed);
	}

	/*/////////////////////////////////////////////////////
						Modifiers
	/////////////////////////////////////////////////////*/

	// modifier checkInputSize(uint256 size0, uint256 size1) {
	// 	if (size0 != size1) revert InputSizeNotAppropriate();
	// 	_;
	// }

	modifier harvestLock() {
		if (harvestLedger.isOpen) revert OnGoingHarvest();
		_;
	}

	/*/////////////////////////////////////////////////////
						Events
	/////////////////////////////////////////////////////*/

	event AddVault(address vault, uint16 chainId, address adapter);
	event UpdateVaultAdapter(address vault, address adapter);
	event ChangeVaultStatus(address vault, bool status);

	/*/////////////////////////////////////////////////////
						Errors
	/////////////////////////////////////////////////////*/

	// error InputSizeNotAppropriate();
	error HarvestNotOpen();
	// error InsufficientReturnOut();
	error VaultNotAllowed(address vault);
	error VaultAlreadyAdded();
	error SlippageExceeded();
	error OnGoingHarvest();
	error EmergencyNotEnabled();
}
