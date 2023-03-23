// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { BytesLib } from "./libraries/BytesLib.sol";
import { BeaconProxy, Address } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { OwnableTransfer } from "./common/OwnableTransfer.sol";
import { SectorBeacon } from "./SectorBeacon.sol";

// import "hardhat/console.sol";

/// @title Scion Vault Factory
/// @author 0x0scion (based on Rari Vault Factory)
/// @notice Upgradable beacon factory which enables deploying a deterministic Vault for ERC20 token.
contract SectorFactory is OwnableTransfer {
	using BytesLib for address;
	using BytesLib for bytes32;

	// length of the deployed vault array
	uint256 public totalVaults;

	/*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

	/// @notice Creates a Vault factory.
	constructor() Ownable() {}

	/// @notice ownership transfer

	/// @notice Upgrades are handled seprately via beacon
	mapping(string => address) public beacons;
	string[] public vaultTypes;
	uint256 public totalVaultTypes;

	function getAllVaultTypes() external view returns (string[] memory) {
		return vaultTypes;
	}

	function addVaultType(string calldata _vaultType, address _beacon) public onlyOwner {
		if (beacons[_vaultType] != address(0)) revert VaultTypeExists();
		beacons[_vaultType] = _beacon;
		vaultTypes.push(_vaultType);
		totalVaultTypes++;
	}

	function implementation(string calldata _vaultType) external view returns (address) {
		return SectorBeacon(beacons[_vaultType]).implementation();
	}

	/*///////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Emitted when a new Vault is deployed.
	/// @param vault The newly deployed Vault contract.
	/// @param vaultType Vault type.
	event AddVault(address vault, string vaultType);

	/// @notice Deploys an SectorAggregator vault.
	/// @return vault The newly deployed Vault contract which accepts the provided underlying token.
	function deployVault(string calldata _vaultType, bytes memory _callData)
		external
		onlyOwner
		returns (address vault)
	{
		address beacon = beacons[_vaultType];
		if (beacon == address(0)) revert MissingVaultType();
		// Use the CREATE2 opcode to deploy a new Vault contract.

		// use both id and chain id as salt
		bytes32 salt = bytes32(abi.encodePacked(uint16(totalVaults), uint16(block.chainid)));

		vault = address(new BeaconProxy{ salt: salt }(beacon, ""));
		// call initialization method
		Address.functionCall(vault, _callData);

		emit AddVault(address(vault), _vaultType);
		totalVaults += 1;
	}

	/*///////////////////////////////////////////////////////////////
                            VAULT LOOKUP LOGIC
    //////////////////////////////////////////////////////////////*/

	/// @notice Computes a Vault's address from its accepted underlying token.
	/// @return The address of a Vault which accepts the provided underlying token.
	/// @dev The Vault returned may not be deployed yet. Use isVaultDeployed to check.
	function getVaultById(string memory _vaultType, uint256 id) external view returns (address) {
		return getVaultById(_vaultType, block.chainid, id);
	}

	/// @notice Computes a Vault's address from its accepted underlying token.
	/// @return The address of a Vault which accepts the provided underlying token.
	/// @dev The Vault returned may not be deployed yet. Use isVaultDeployed to check.
	function getVaultById(
		string memory _vaultType,
		uint256 chainId,
		uint256 id
	) public view returns (address) {
		return
			address(
				keccak256(
					abi.encodePacked(
						// Prefix:
						bytes1(0xFF),
						// Creator:
						address(this),
						// Salt:
						bytes32(abi.encodePacked(uint16(id), uint16(chainId))),
						// Bytecode hash:
						keccak256(
							abi.encodePacked(
								// Deployment bytecode:
								type(BeaconProxy).creationCode,
								// Constructor arguments:
								abi.encode(beacons[_vaultType], "")
							)
						)
					)
				).fromLast20Bytes() // Convert the CREATE2 hash into an address.
			);
	}

	error VaultTypeExists();
	error MissingVaultType();
}
