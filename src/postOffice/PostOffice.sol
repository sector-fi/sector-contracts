// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPostman } from "../interfaces/postOffice/IPostman.sol";
import "../interfaces/MsgStructs.sol";

struct Client {
	uint16 chainId;
	uint16 postmanId;
}

struct AddressBook {
	mapping(address => Client) info;
	address[] addr;
	mapping(uint16 => address) postman;
	mapping(address => bool) isPostman;
	address[] postmanList;
}

/* This lives in MsgStructs
struct Message {
    uint256 value;
    address sender;
    uint16 chainId;
}
*/

contract PostOffice is Ownable {
	mapping(address => mapping(messageType => Message[])) internal messageBoard;
	AddressBook internal addrBook;

	constructor() {
		addrBook.postman[0] = 0;
	}

	/*/////////////////////////////////////////////////////
						Messaging API
	/////////////////////////////////////////////////////*/

	function sendMessage(
		address receiverAddr,
		Message message,
		messageType msgType
	) external {
		if (addrBook.info[msg.sender].chainId != block.chainid)
			revert SenderNotAllowed(message.sender, message.chainId);

		Client receiver = addrBook.info[receiverAddr];

		if (receiver.adapterId == 0) revert AddressNotInBook(receiverAddr);

		IPostman(addrBook.adapter[receiver.adapterId]).deliverMessage(
			receiverAddr,
			message,
			msgType
		);
		emit MessageSent(receiverAddr, message.value, message.sender, message.chainId, msgType);
	}

	function writeMessage(
		address receiver,
		Message message,
		messageType msgType
	) external isPostman(msg.sender) {
		if (!xChainIntegrator(receiver).isSenderAllowed(message))
			revert SenderNotAllowed(message.sender, message.chainId);

		messageBoard[receiver][msgType].push(message);

		emit MessageReceived(receiver, message.value, message.sender, message.chainId, msgType);
	}

	// This function will consume all messages from board
	// for a specific type of message
	function readMessage(messageType msgType) external returns (Message[] memory messages) {
		// Read from storage
		Message[] storage storagedMessages = messageBoard[msg.sender][msgType];

		uint256 length = storagedMessages.length;
		messages = new Message[](length);

		for (uint256 i = length; i > 0; ) {
			messages[i - 1] = storagedMessages[i - 1];
			storagedMessages.pop();

			unchecked {
				i++;
			}
		}

		return messages;
	}

	// Returns only total value on board
	// Gas is cheaper here and consumer doesn't need to loop a response
	function readMessageReduce(messageType msgType) external returns (uint256 total) {
		Message[] storage storagedMessages = messageBoard[msg.sender][msgType];
		total = 0;

		for (uint256 i = storagedMessages.length; i > 0; ) {
			total += storagedMessages[i - 1].value;
			storagedMessages.pop();

			unchecked {
				i++;
			}
		}

		return total;
	}

	/*/////////////////////////////////////////////////////
					Manage addresses/postmen
	/////////////////////////////////////////////////////*/

	function addClient(address _client, uint16 postmanId) external onlyOwner {
		_addClient(_client, postmanId, block.chainid);
	}

	function addClient(
		address _client,
		uint16 postmanId,
		uint16 chainId
	) external onlyOwner {
		_addClient(_client, postmanId, chainId);
	}

	function addPostman(address _postman) external onlyOwner {
		if (addrBook.postman[_postman] != address(0)) revert PostmanAlreadyAdded();
		addrBook.postmanList.push(_postman);

		uint256 id = addrBook.postmanList.length;
		addrBook.postman[id] = _postman;

		emit PostmanAdded(_postman, id);
	}

	function updateReceiver(address receiver, uint16 newPostmanId) external onlyOwner {
		addrBook.info[receiver].postmanId = newPostmanId;

		emit ReceiverUpdated(receiver, newPostmanId);
	}

	function updatePostman(uint16 postmanId, address newAddr) external onlyOwner {
		addrBook.postmanList[postmanId] = newAddr;
		addrBook.postman[postmanId] = newAddr;

		emit PostmanUpdated(newAddr, postmanId);
	}

	function listReceivers() public returns (address[]) {
		uint256 length = addrBook.addr.length;
		address[] receivers = new address[](length);

		for (uint256 i = 0; i < length; ) {
			receivers[i] = addrBook.addr[i];

			unchecked {
				i++;
			}
		}

		return receivers;
	}

	function listPostman() public returns (address[]) {
		uint256 length = addrBook.postmanList.length;
		address[] postmen = new address[](length);

		for (uint256 i = 0; i < length; ) {
			postmen[i] = addrBook.postmanList[i];

			unchecked {
				i++;
			}
		}

		return postmen;
	}

	function _addClient(
		address _client,
		uint16 postmanId,
		uint16 chainId
	) internal {
		if (addrBook.info[_client].adapterId != 0) revert ClientAlreadyAdded();

		addrBook.info[_client] = Client(_client, chainId, postmanId);
		addrBook.addr.push(_client);

		emit ClientAdded(_client, chainId, postmanId);
	}

	/*/////////////////////////////////////////////////////
				Modifiers, events and errors
	/////////////////////////////////////////////////////*/

	modifier isPostman(address postman) {
		if (!addrBook.isPostman[postman]) revert OnlyPostmanAllowed();
		_;
	}

	event MessageReceived(
		address receiver,
		uint256 value,
		address sender,
		uint16 srcChainId,
		messageType mType
	);
	event MessageSent(
		address receiver,
		uint256 value,
		address sender,
		uint16 dstChainId,
		messageType mtype
	);
	event ClientAdded(address client, uint16 chainId, uint16 postmanId);
	event PostmanAdded(address postman, uint16 postmanId);
	event ReceiverUpdated(address receiver, uint16 postmanId);
	event PostmanUpdated(address newAddr, uint16 postmanId);

	error SenderNotAllowed(address sender, uint16 chainId);
	error AddressNotInBook(address receiver);
	error OnlyPostmanAllowed();
	error ClientAlreadyAdded();
	error PostmanAlreadyAdded();
}
