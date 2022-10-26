// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Auth } from "../../common/Auth.sol";
import "../../interfaces/MsgStructs.sol";
import "../../interfaces/postOffice/IPostman.sol";
// import "hardhat/console.sol";

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

abstract contract XChainIntegrator is Auth {
	// mapping(address => mapping(uint16 => Vault)) public addrBook;
	mapping(address => Vault) public addrBook;
	mapping(uint16 => mapping(uint16 => address)) public postmanAddr;
	mapping(address => mapping(uint16 => address)) public xAddr;
	Message[] public incomingQueue;

	uint16 immutable chainId = uint16(block.chainid);

	// A fixed point number where 1e18 represents 100% and 0 represents 0%.
	uint256 public maxBridgeFeeAllowed;

	constructor(uint256 _maxBridgeFeeAllowed) {
		maxBridgeFeeAllowed = _maxBridgeFeeAllowed;
	}

	/*/////////////////////////////////////////////////////
						Bridge utilities
	/////////////////////////////////////////////////////*/

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
	) internal pure {
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
	}

	/// @notice Sends tokens using Bungee middleware. Assumes tokens already present in contract. Manages allowance and transfer.
	/// @dev Currently not verifying the middleware request calldata. Use very carefully
	/// @param allowanceTarget address to allow tokens to swipe
	/// @param socketRegistry address to send bridge txn to
	/// @param destinationAddress address of receiver
	/// @param amount amount of tokens to bridge
	/// @param destinationChainId chain Id of receiving chain
	/// @param data calldata of txn to be sent
	function _sendTokens(
		address asset,
		address allowanceTarget,
		address socketRegistry,
		address destinationAddress,
		uint256 amount,
		uint256 destinationChainId,
		bytes calldata data
	) internal onlyRole(MANAGER) {
		verifySocketCalldata(data, destinationChainId, asset, destinationAddress);

		ERC20(asset).approve(allowanceTarget, amount);
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

	function checkBridgeFee(uint256 amount, uint256 fee) public view {
		if (maxBridgeFeeAllowed * amount < fee * 1e18) revert MaxBridgeFee();
	}

	function setMaxBridgeFee(uint256 _maxFee) external onlyRole(GUARDIAN) {
		maxBridgeFeeAllowed = _maxFee;

		emit SetMaxBridgeFee(_maxFee);
	}

	/*/////////////////////////////////////////////////////
					Address book management
	/////////////////////////////////////////////////////*/

	function addVault(
		address _vault,
		uint16 _chainId,
		uint16 _postmanId,
		bool _allowed
	) external virtual onlyOwner {
		_addVault(_vault, _chainId, _postmanId, _allowed);
	}

	function _addVault(
		address _vault,
		uint16 _chainId,
		uint16 _postmanId,
		bool _allowed
	) internal onlyOwner {
		address xVaultAddr = getXAddr(_vault, _chainId);
		Vault memory vault = addrBook[xVaultAddr];

		if (vault.allowed) revert VaultAlreadyAdded();

		addrBook[xVaultAddr] = Vault(_postmanId, _allowed);
		emit AddedVault(_vault, _chainId);
	}

	function changeVaultStatus(
		address _vault,
		uint16 _chainId,
		bool _allowed
	) external onlyOwner {
		addrBook[getXAddr(_vault, _chainId)].allowed = _allowed;

		emit ChangedVaultStatus(_vault, _chainId, _allowed);
	}

	function updateVaultPostman(
		address _vault,
		uint16 _chainId,
		uint16 _postmanId
	) external onlyOwner {
		address xVaultAddr = getXAddr(_vault, _chainId);
		Vault memory vault = addrBook[xVaultAddr];

		if (vault.postmanId == 0) revert VaultMissing(_vault);

		addrBook[xVaultAddr].postmanId = _postmanId;

		emit UpdatedVaultPostman(_vault, _chainId, _postmanId);
	}

	function managePostman(
		uint16 _postmanId,
		uint16 _chainId,
		address _postman
	) external onlyOwner {
		postmanAddr[_postmanId][_chainId] = _postman;

		emit PostmanUpdated(_postmanId, _chainId, _postman);
	}

	/*/////////////////////////////////////////////////////
					Cross-chain logic
	/////////////////////////////////////////////////////*/

	// Mising chainId info
	function _sendMessage(
		address receiverAddr,
		uint16 receiverChainId,
		Vault memory vault,
		Message memory message,
		MessageType msgType
	) internal {
		address srcPostman = postmanAddr[vault.postmanId][chainId];
		address dstPostman = postmanAddr[vault.postmanId][receiverChainId];
		if (srcPostman == address(0)) revert MissingPostman(vault.postmanId, chainId);
		if (dstPostman == address(0)) revert MissingPostman(vault.postmanId, receiverChainId);

		uint256 messageFee = _estimateMessageFee(receiverAddr, receiverChainId, message, msgType, srcPostman);

		if (address(this).balance < messageFee) revert InsufficientBalanceToSendMessage();

		IPostman(srcPostman).deliverMessage{ value: messageFee }(
			message,
			receiverAddr,
			dstPostman,
			msgType,
			receiverChainId
		);

		emit MessageSent(message.value, receiverAddr, receiverChainId, msgType, srcPostman);
	}

	function receiveMessage(Message calldata _msg, MessageType _type) external {
		// First check if postman is allowed
		Vault memory vault = addrBook[getXAddr(_msg.sender, _msg.chainId)];
		if (!vault.allowed) revert SenderNotAllowed(_msg.sender);
		if (msg.sender != postmanAddr[vault.postmanId][chainId]) revert WrongPostman(msg.sender);

		// messageAction[_type](_msg);
		_handleMessage(_type, _msg);
		emit MessageReceived(_msg.value, _msg.sender, _msg.chainId, _type, msg.sender);
	}

	function getXAddr(address xVault, uint16 _chainId) public returns (address computed) {
		computed = xAddr[xVault][_chainId];
		if (computed != address(0)) return computed;

		computed = address(uint160(uint(keccak256(abi.encodePacked(_chainId, xVault)))));
		xAddr[xVault][_chainId] = computed;
	}

	function getIncomingQueue() public view returns (Message[] memory) {
		return incomingQueue;
	}

	function getIncomingQueueLength() public view returns (uint256) {
		return incomingQueue.length;
	}

	function _handleMessage(MessageType _type, Message calldata _msg) internal virtual {}

	function _estimateMessageFee(
		address receiverAddr,
		uint16 receiverChainId,
		Message memory message,
		MessageType msgType,
		address srcPostman
	) internal view returns (uint256) {
		uint256 messageFee = IPostman(srcPostman).estimateFee(
			receiverChainId,
			receiverAddr,
			msgType,
			message
		);

		return messageFee;
	}

	function estimateMessageFee(Request[] calldata vaults, MessageType _msgType)
		external
		returns (uint256)
	{
		uint256 totalFees = 0;
		for (uint256 i = 0; i < vaults.length; ) {
			address vaultAddr = vaults[i].vaultAddr;
			uint16 vaultChainId = vaults[i].vaultChainId;
			uint256 amount = vaults[i].amount;

			Vault memory vault = addrBook[getXAddr(vaultAddr, vaultChainId)];
			address srcPostman = postmanAddr[vault.postmanId][chainId];

			totalFees += _estimateMessageFee(
				vaultAddr,
				vaultChainId,
				Message(amount, address(this), address(0), chainId),
				_msgType,
				srcPostman
			);

			unchecked {
				i++;
			}
		}

		return totalFees;
	}

	function processIncomingXFunds() external virtual {}

	/*/////////////////////////////////////////////////////
							Events
	/////////////////////////////////////////////////////*/

	event MessageReceived(
		uint256 value,
		address indexed sender,
		uint16 indexed srcChainId,
		MessageType mType,
		address postman
	);
	event MessageSent(
		uint256 value,
		address indexed receiver,
		uint16 indexed dstChainId,
		MessageType mtype,
		address postman
	);
	event AddedVault(address indexed vault, uint16 chainId);
	event ChangedVaultStatus(address indexed vault, uint16 indexed chainId, bool status);
	event UpdatedVaultPostman(address indexed vault, uint16 indexed chainId, uint16 postmanId);
	event PostmanUpdated(uint16 indexed postmanId, uint16 chanId, address postman);
	event BridgeAsset(uint16 _fromChainId, uint16 _toChainId, uint256 amount);
	event RegisterIncomingFunds(uint256 total);
	event SetMaxBridgeFee(uint256 _maxFee);

	/*/////////////////////////////////////////////////////
							Errors
	/////////////////////////////////////////////////////*/

	error MissingPostman(uint16 postmanId, uint256 chainId);
	error SenderNotAllowed(address sender);
	error WrongPostman(address postman);
	error VaultNotAllowed(address vault, uint16 chainId);
	error VaultMissing(address vault);
	error VaultAlreadyAdded();
	error BridgeError();
	error SameChainOperation();
	error MissingIncomingXFunds();
	error MaxBridgeFee();
	error InsufficientBalanceToSendMessage();
}