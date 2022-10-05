// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { ERC4626 } from "./ERC4626/ERC4626.sol";
import { ILayerZeroReceiver } from "../interfaces/LayerZero/ILayerZeroReceiver.sol";
import { ILayerZeroEndpoint } from "../interfaces/LayerZero/ILayerZeroEndpoint.sol";
import { ILayerZeroUserApplicationConfig } from "../interfaces/LayerZero/ILayerZeroUserApplicationConfig.sol";

// import "hardhat/console.sol";

struct vault {
	// uint256 assetAmount;
	// uint256 shareAmount;
	// uint256 pendingShareAmount;
	// uint256 sharesToUnderlying;
	uint256 chainId;
	address adapter;
	bool 	allowed;
}

contract SectorCrossVault is BatchedWithdraw, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
	mapping(uint256 => mapping(address => bool)) public sectorVaultsWhitelist;
	ILayerZeroEndpoint public endpoint;

	// uint256 public totalDeposited;

	// Controls deposits
	mapping(address => vault) public depositedVaults;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee,
		address _layerZeroEndpoint
	) ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {
		endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
	}

	/* CROSS VAULT */

	function depositIntoVaults(
		address[] calldata vaults,
		uint256[] calldata amounts
		// uint256[] calldata minSharesOut
	) public onlyRole(MANAGER) checkInputSize([vaults.length, amounts.length]) {
		for (uint i = 0; i < vaults.length;) {
			if (!depositedVaults[vaults[i]].allowed) revert VaultNotAllowed(vaults[i]);

			depositedVaults[vaults[i]].adapter == address(0)
				? ERC4626(vaults[i])
					.deposit(amounts[i], address(this))
				: IXMESSAGER(depositedVaults[vaults[i]].adapter)
					.deposit(amounts[i], address(this), depositedVaults[vaults[i]].chainId);

			// if (sharesOut < minSharesOut[i]) revert InsufficientReturnOut();

			// totalDeposited += amounts[i];
			// depositedVaults[vaults[i]].assetAmount += amounts[i];
			// depositedVaults[vaults[i]].shareAmount += sharesOut;
			unchecked { i++; }
		}
	}

	function requestRedeemFromVaults(
		address[] calldata vaults,
		uint256[] calldata shares
	) public onlyRole(MANAGER) checkInputSize([vaults.length, shares.length]) {
		for (uint i = 0; i < vaults.length;) {
			if (!depositedVaults[vaults[i]].allowed) revert VaultNotAllowed(vaults[i]);

			depositedVaults[vaults[i]].adapter == address(0)
				? ERC4626(vaults[i])
					.requestRedeem(shares[i])
				: IXMESSAGER(vaults[i])
					.requestRedeem(shares[i], depositedVaults[vaults[i]].chainId);

			unchecked { i++; }
		}
	}

	function redeemFromVaults(
		address[] calldata vaults,
		uint256[] calldata shares
	) public onlyRole(MANAGER) checkInputSize([vaults.length, shares.length]) {
		for (uint i = 0; i < vaults.length;) {
			if (!depositedVaults[vaults[i]].allowed) revert VaultNotAllowed(vaults[i]);

			depositedVaults[vaults[i]].adapter == address(0)
				? ERC4626(vaults[i])
					.requestRedeem(shares[i])
				: IXMESSAGER(vaults[i])
					.requestRedeem(shares[i], depositedVaults[vaults[i]].chainId);
			// Not sure if it should request manager intervention after redeem when in different chains

			unchecked { i++; }
		}
	}

	// function harvestVaults(
	// 	address[] calldata vaults,
	// 	HarvestSwapParms[] calldata harvestParams
	// ) public onlyRole(MANAGER) checkInputSize([vaults.length, harvestParams.length]) {
	// 	for (uint i = 0; i < vaults.length;) {
	// 		// No idea how to call harvest and how to map swap params with harvest call
	// 		vaults[i].harvest(harvestParams.min, harvestStrategies.deadline);

	// 		unchecked { i++; }
	// 	}
	// }

	modifier checkInputSize(uint[2] memory inputSizes) {
		for (uint i = 1; i < inputSizes.length;) {
			if (inputSizes[i - 1] != inputSizes[i]) {
				revert InputSizeNotAppropriate();
			}

			unchecked {
				i++;
			}
		}
		_;
	}

	/* BRIDGE FUNCTIONALLITY */

	/// @notice Struct encoded in Bungee calldata
	/// @dev Derived from socket registry contract
	struct MiddlewareRequest {
		uint256 id;
		uint256 optionalNativeAmount;
		address inputToken;
		bytes data;
	}

	/// @notice Struct encoded in Bungee calldata
	/// @dev Derived from socket registry contract
	struct BridgeRequest {
		uint256 id;
		uint256 optionalNativeAmount;
		address inputToken;
		bytes data;
	}

	/// @notice Struct encoded in Bungee calldata
	/// @dev Derived from socket registry contract
	struct UserRequest {
		address receiverAddress;
		uint256 toChainId;
		uint256 amount;
		MiddlewareRequest middlewareRequest;
		BridgeRequest bridgeRequest;
	}

	/// @notice Decode the socket request calldata
	/// @dev Currently not in use due to undertainity in bungee api response
	/// @param _data Bungee txn calldata
	/// @return userRequest parsed calldata
	function decodeSocketRegistryCalldata(bytes memory _data)
		internal
		pure
		returns (UserRequest memory userRequest)
	{
		bytes memory callDataWithoutSelector = slice(_data, 4, _data.length - 4);
		(userRequest) = abi.decode(callDataWithoutSelector, (UserRequest));
	}

	/// @notice Decodes and verifies socket calldata
	/// @param _data Bungee txn calldata
	/// @param _chainId chainId to check in bungee calldata
	/// @param _inputToken inputWantToken to check in bungee calldata
	/// @param _receiverAddress receiving address to check in bungee calldata
	function verifySocketCalldata(
		bytes memory _data,
		uint256 _chainId,
		address _inputToken,
		address _receiverAddress
	) internal view {
		UserRequest memory userRequest;
		(userRequest) = decodeSocketRegistryCalldata(_data);

		if (userRequest.toChainId != _chainId) {
			revert("Invalid chainId");
		}
		if (userRequest.receiverAddress != _receiverAddress) {
			revert("Invalid receiver address");
		}
		if (userRequest.bridgeRequest.inputToken != _inputToken) {
			revert("Invalid input token");
		}

		if (!sectorVaultsWhitelist[_chainId][userRequest.receiverAddress])
			revert ReceiverNotWhiteslisted(_receiverAddress);
	}

	// Who should be responsible for whitelist vaults?
	// I believe it's the guardian
	function whitelistSectorVault(uint32 chainId, address _vault) external onlyOwner {
		sectorVaultsWhitelist[chainId][_vault] = true;
		emit WhitelistedSectorVault(chainId, _vault);
	}

	// function checkWhitelistVault(uint32 chainId, address vault) external view returns (bool) {
	// 	return sectorVaultsWhitelist[chainId][vault];
	// }

	// Added function to emit event
	// This one has to integrate with layerZero message sender
	function startDepositCrosschainRequest(
		uint32 _fromChainId,
		uint32 _toChainId,
		uint256 amount
	) public {
		emit BridgeAsset(_fromChainId, _toChainId, amount);
	}

	// This function will change to depositCrossChain
	/// @notice Sends tokens using Bungee middleware. Assumes tokens already present in contract. Manages allowance and transfer.
	/// @dev Currently not verifying the middleware request calldata. Use very carefully
	/// @param allowanceTarget address to allow tokens to swipe
	/// @param socketRegistry address to send bridge txn to
	/// @param destinationAddress address of receiver
	/// @param amount amount of tokens to bridge
	/// @param destinationChainId chain Id of receiving chain
	/// @param data calldata of txn to be sent
	function sendTokens(
		address allowanceTarget,
		address socketRegistry,
		address destinationAddress,
		uint256 amount,
		uint256 destinationChainId,
		bytes calldata data
	) public onlyRole(MANAGER) {
		verifySocketCalldata(data, destinationChainId, address(_asset), destinationAddress);

		_asset.approve(msg.sender, amount);
		_asset.approve(allowanceTarget, amount);
		(bool success, ) = socketRegistry.call(data);

		if (!success) revert BridgeError();
	}

	/*
	 * @notice Helper to slice memory bytes
	 * @author Gonçalo Sá <goncalo.sa@consensys.net>
	 *
	 * @dev refer https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol
	 */
	function slice(
		bytes memory _bytes,
		uint256 _start,
		uint256 _length
	) internal pure returns (bytes memory) {
		require(_length + 31 >= _length, "slice_overflow");
		require(_bytes.length >= _start + _length, "slice_outOfBounds");

		bytes memory tempBytes;

		assembly {
			switch iszero(_length)
			case 0 {
				// Get a location of some free memory and store it in tempBytes as
				// Solidity does for memory variables.
				tempBytes := mload(0x40)

				// The first word of the slice result is potentially a partial
				// word read from the original array. To read it, we calculate
				// the length of that partial word and start copying that many
				// bytes into the array. The first word we copy will start with
				// data we don't care about, but the last `lengthmod` bytes will
				// land at the beginning of the contents of the new array. When
				// we're done copying, we overwrite the full first word with
				// the actual length of the slice.
				let lengthmod := and(_length, 31)

				// The multiplication in the next line is necessary
				// because when slicing multiples of 32 bytes (lengthmod == 0)
				// the following copy loop was copying the origin's length
				// and then ending prematurely not copying everything it should.
				let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
				let end := add(mc, _length)

				for {
					// The multiplication in the next line has the same exact purpose
					// as the one above.
					let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
				} lt(mc, end) {
					mc := add(mc, 0x20)
					cc := add(cc, 0x20)
				} {
					mstore(mc, mload(cc))
				}

				mstore(tempBytes, _length)

				//update free-memory pointer
				//allocating the array padded to 32 bytes like the compiler does now
				mstore(0x40, and(add(mc, 31), not(31)))
			}
			//if we want a zero-length slice let's just return a zero-length array
			default {
				tempBytes := mload(0x40)
				//zero out the 32 bytes slice we are about to return
				//we need to do it because Solidity does not garbage collect
				mstore(tempBytes, 0)

				mstore(0x40, add(tempBytes, 0x20))
			}
		}

		return tempBytes;
	}

	/* CROSS CHAIN MESSAGING */

	function sendMessage(
		uint16 _dstChainId,
		address _dstVaultAddress,
		uint256 _amount
	) public {
		if (address(this).balance == 0) revert NoBalance();

		bytes memory payload = abi.encode(_amount);

		// encode adapterParams to specify more gas for the destination
		uint16 version = 1;
		uint256 gasForDestinationLzReceive = 350000;
		bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

		(uint256 messageFee, ) = endpoint.estimateFees(
			_dstChainId,
			address(this),
			payload,
			false,
			adapterParams
		);
		if (address(this).balance < messageFee) revert InsufficientBalanceToSendMessage();

		// send LayerZero message
		endpoint.send{ value: messageFee }( // {value: messageFee} will be paid out of this contract!
			_dstChainId, // destination chainId
			abi.encodePacked(_dstVaultAddress), // destination address of PingPong
			payload, // abi.encode()'ed bytes
			payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
			address(0x0), // 'zroPaymentAddress' unused for this mock/example
			adapterParams // 'adapterParams' unused for this mock/example
		);
	}

	// receive the bytes payload from the source chain via LayerZero
	// _srcChainId: the chainId that we are receiving the message from.
	// _fromAddress: the source PingPong address
	function lzReceive(
		uint16 _srcChainId,
		bytes memory _fromAddress,
		uint64, /*_nonce*/
		bytes memory _payload
	) external override {
		require(msg.sender == address(endpoint)); // boilerplate! lzReceive must be called by the endpoint for security

		// use assembly to extract the address from the bytes memory parameter
		address fromAddress;
		assembly {
			fromAddress := mload(add(_fromAddress, 20))
		}

		// decode decode amount sent from source chain
		uint256 _amount = abi.decode(_payload, (uint256));

		emit MessageReceived(_srcChainId, fromAddress, _amount);
	}

	function setConfig(
		uint16, /*_version*/
		uint16 _dstChainId,
		uint256 _configType,
		bytes memory _config
	) external override {
		endpoint.setConfig(
			_dstChainId,
			endpoint.getSendVersion(address(this)),
			_configType,
			_config
		);
	}

	function getConfig(
		uint16, /*_dstChainId*/
		uint16 _chainId,
		address,
		uint256 _configType
	) external view returns (bytes memory) {
		return
			endpoint.getConfig(
				endpoint.getSendVersion(address(this)),
				_chainId,
				address(this),
				_configType
			);
	}

	function setSendVersion(uint16 version) external override {
		endpoint.setSendVersion(version);
	}

	function setReceiveVersion(uint16 version) external override {
		endpoint.setReceiveVersion(version);
	}

	function getSendVersion() external view returns (uint16) {
		return endpoint.getSendVersion(address(this));
	}

	function getReceiveVersion() external view returns (uint16) {
		return endpoint.getReceiveVersion(address(this));
	}

	function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override {
		// do nth
	}

	// allow this contract to receive ether
	fallback() external payable {}

	receive() external payable {}

	/* EVENTS */
	event BridgeAsset(uint32 _fromChainId, uint32 _toChainId, uint256 amount);
	event WhitelistedSectorVault(uint32 chainId, address sectorVault);
	event MessageReceived(uint16 _srcChainId, address fromAddress, uint256 amount);

	/* ERRORS */
	error InsufficientBalanceToSendMessage();
	error NoBalance();
	error InputSizeNotAppropriate();
	error InsufficientReturnOut();
	error BridgeError();
	error ReceiverNotWhiteslisted(address receiver);
	error VaultNotAllowed(address vault);
}
