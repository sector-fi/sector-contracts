// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BatchedWithdraw } from "./ERC4626/BatchedWithdraw.sol";
import { ERC4626 } from "./ERC4626/ERC4626.sol";

// import "hardhat/console.sol";

contract SectorCrossVault is BatchedWithdraw {
	mapping(uint256 => mapping(address => bool)) public sectorVaultsWhitelist;

	// HAS TO REVERT FUNCTION CALLS FROM ERC20
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

	/* CROSS VAULT */

	function depositIntoVaults(
		address[] calldata vaults,
		uint256[] calldata amounts,
		uint256[] calldata minSharesOut
	)
		public
		onlyRole(MANAGER)
		checkInputSize([vaults.length, amounts.length, minSharesOut.length])
	{
		for (uint256 i = 0; i < vaults.length; ) {
			if (ERC4626(vaults[i]).deposit(amounts[i], address(this)) < minSharesOut[i]) {
				revert InsufficientReturnOut();
			}

			unchecked {
				i++;
			}
		}
	}

	function withdrawFromVaults(
		address[] calldata vaults,
		uint256[] calldata shares,
		uint256[] calldata minAmountOut
	) public onlyRole(MANAGER) checkInputSize([vaults.length, shares.length, minAmountOut.length]) {
		for (uint256 i = 0; i < vaults.length; ) {
			if (
				ERC4626(vaults[i]).withdraw(shares[i], address(this), address(this)) <
				minAmountOut[i]
			) {
				revert InsufficientReturnOut();
			}

			unchecked {
				i++;
			}
		}
	}

	/// TODO Has to update shares value looking into deposited vaults (including cross vault stuff)
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

	// TODO Move modifier to end of file
	// Solidity type system is not allowing me to use uint[]
	modifier checkInputSize(uint256[3] memory inputSizes) {
		for (uint256 i = 1; i < inputSizes.length; ) {
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
	function whitelistSectorVault(uint32 chainId, address _vault) external onlyRole(GUARDIAN) {
		sectorVaultsWhitelist[chainId][_vault] = true;
		emit WhitelistedSectorVault(chainId, _vault);
	}

	function checkWhitelistVault(uint32 chainId, address vault) external view returns (bool) {
		return sectorVaultsWhitelist[chainId][vault];
	}

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

	/* EVENTS */
	event BridgeAsset(uint32 _fromChainId, uint32 _toChainId, uint256 amount);
	event WhitelistedSectorVault(uint32 chainId, address sectorVault);

	/* ERRORS */
	error InputSizeNotAppropriate();
	error InsufficientReturnOut();
	error BridgeError();
	error ReceiverNotWhiteslisted(address receiver);
}
