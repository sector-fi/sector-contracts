// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { ERC4626 } from "./ERC4626/ERC4626.sol";
import { IXAdapter } from "../interfaces/adapters/IXAdapter.sol";
import { SocketIntegrator } from "../common/SocketIntegrator.sol";

// import "hardhat/console.sol";

contract SectorCrossVault is BatchedWithdraw, SocketIntegrator {
	enum msgType {
		NONE,
		DEPOSIT,
		REDEEM,
		REQUESTREDEEM,
		REQUESTVALUEOFSHARES
	}

	struct Vault {
		uint16 chainId;
		address adapter;
		bool allowed;
	}

	struct Request {
		uint256 timestamp;
		uint256 chainId;
		address vault;
	}

	struct HarvestLedger {
		uint256 depositValue;
		bool isOpen;
		uint256 openIndex;
		Request[] request;
	}

	// emergencyWithdraw
	// Keep track of depositedVaults
	// Loop through them and transfer shares to user
	// Do that xcross chain as well

	// Controls deposits
	mapping(address => Vault) public depositedVaults;

	// Harvest state
	HarvestLedger public harvestLedger;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee
	) ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {
		// Not sure if needed
		harvestLedger.openIndex = 0;
		harvestLedger.isOpen = false;
		harvestLedger.depositValue = 0;
	}

	/*/////////////////////////////////////////////////////
					Cross Vault Interface
	/////////////////////////////////////////////////////*/

	function depositIntoVaults(address[] calldata vaults, uint256[] calldata amounts)
		public
		onlyRole(MANAGER)
		checkInputSize(vaults.length, amounts.length)
	{
		for (uint256 i = 0; i < vaults.length; ) {
			Vault memory tmpVault = depositedVaults[vaults[i]];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaults[i]);

			if (tmpVault.adapter == address(0)) {
				BatchedWithdraw(vaults[i]).deposit(amounts[i], address(this));
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					amounts[i],
					vaults[i],
					address(this),
					tmpVault.chainId,
					uint16(msgType.DEPOSIT),
					uint16(block.chainid)
				);

				emit BridgeAsset(uint16(block.chainid), tmpVault.chainId, amounts[i]);
			}

			unchecked {
				i++;
			}
		}
	}

	function requestRedeemFromVaults(address[] calldata vaults, uint256[] calldata shares)
		public
		onlyRole(MANAGER)
		checkInputSize(vaults.length, shares.length)
	{
		for (uint256 i = 0; i < vaults.length; ) {
			Vault memory tmpVault = depositedVaults[vaults[i]];

			if (!tmpVault.allowed) revert VaultNotAllowed(vaults[i]);

			if (tmpVault.adapter == address(0)) {
				BatchedWithdraw(vaults[i]).requestRedeem(shares[i]);
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					shares[i],
					vaults[i],
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

	function redeemFromVaults(address[] calldata vaults, uint256[] calldata shares)
		public
		onlyRole(MANAGER)
		checkInputSize(vaults.length, shares.length)
	{
		for (uint256 i = 0; i < vaults.length; ) {
			Vault memory tmpVault = depositedVaults[vaults[i]];

			if (tmpVault.allowed) revert VaultNotAllowed(vaults[i]);

			if (tmpVault.adapter == address(0)) {
				BatchedWithdraw(vaults[i]).redeem(shares[i], address(this), address(this));
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					shares[i],
					vaults[i],
					address(this),
					tmpVault.chainId,
					uint16(msgType.REDEEM),
					uint16(block.chainid)
				);
			}
			// Not sure if it should request manager intervention after redeem when in different chains

			unchecked {
				i++;
			}
		}
	}

	function harvestVaults(address[] calldata vaults) public onlyRole(MANAGER) {
		uint256 depositValue = 0;

		for (uint256 i = 0; i < vaults.length; ) {
			Vault memory tmpVault = depositedVaults[vaults[i]];

			if (tmpVault.adapter == address(0)) {
				depositValue +=
					BatchedWithdraw(vaults[i]).balanceOf(address(this)) *
					BatchedWithdraw(vaults[i]).getValueOfShares();
				// Check function name
			} else {
				IXAdapter(tmpVault.adapter).sendMessage(
					0,
					vaults[i],
					address(this),
					tmpVault.chainId,
					uint16(msgType.REQUESTVALUEOFSHARES),
					uint16(block.chainid)
				);

				harvestLedger.request.push(Request(block.timestamp, tmpVault.chainId, vaults[i]));
			}
			unchecked {
				i++;
			}
		}

		harvestLedger.depositValue = depositValue;
		harvestLedger.isOpen = true;
	}

	// Add lock to deposits and withdraws

	// Has to pass slippage params here and revert in case of not fitting what is expected.
	function finalizeHarvest() public onlyRole(MANAGER) {
		HarvestLedger memory hLedger = harvestLedger;
		uint256 xValue = 0;

		if (!hLedger.isOpen) revert HarvestNotOpen();

		uint256 i = hLedger.openIndex;
		while (i < hLedger.request.length) {
			Vault memory tmpVault = depositedVaults[hLedger.request[i].vault];

			// If timestamp > message.timestamp transaction will revert
			uint256 value = IXAdapter(tmpVault.adapter).readMessage(
				hLedger.request[i].vault,
				tmpVault.chainId,
				hLedger.request[i].timestamp
			);
			xValue += value;

			unchecked {
				i++;
			}
		}

		sharesToUnderlying = (hLedger.depositValue + xValue) / totalSupply();

		harvestLedger.openIndex = i;
		harvestLedger.depositValue = 0;
		harvestLedger.isOpen = false;
	}

	modifier checkInputSize(uint256 size0, uint256 size1) {
		if (size0 != size1) revert InputSizeNotAppropriate();
		_;
	}

	/*/////////////////////////////////////////////////////
					Vault Management
	/////////////////////////////////////////////////////*/

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
						Events
	/////////////////////////////////////////////////////*/

	event AddVault(address vault, uint16 chainId, address adapter);
	event UpdateVaultAdapter(address vault, address adapter);
	event ChangeVaultStatus(address vault, bool status);
	// event MessageReceived(uint16 _srcChainId, address fromAddress, uint256 amount);

	/*/////////////////////////////////////////////////////
						Errors
	/////////////////////////////////////////////////////*/

	error InputSizeNotAppropriate();
	error HarvestNotOpen();
	// error InsufficientReturnOut();
	// error ReceiverNotWhiteslisted(address receiver);
	error VaultNotAllowed(address vault);
	error VaultAlreadyAdded();
}
