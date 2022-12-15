// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Auth } from "../common/Auth.sol";
import "../interfaces/MsgStructs.sol";
import "../interfaces/xChain/IPostman.sol";
import { XChainLib } from "../libraries/XChainLib.sol";

// import "hardhat/console.sol";

abstract contract XChainIntegrator is Auth {
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
	) internal {
		XChainLib.verifySocketCalldata(data, destinationChainId, asset, destinationAddress);

		IERC20(asset).approve(allowanceTarget, amount);
		(bool success, ) = socketRegistry.call(data);

		if (!success) revert BridgeError();
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

		uint256 messageFee = _estimateMessageFee(
			receiverAddr,
			receiverChainId,
			message,
			msgType,
			srcPostman
		);

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

		computed = address(uint160(uint256(keccak256(abi.encodePacked(_chainId, xVault)))));
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
		for (uint256 i; i < vaults.length; ) {
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
				++i;
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
