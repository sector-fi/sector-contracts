// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ILayerZeroReceiver } from "../interfaces/adapters/ILayerZeroReceiver.sol";
import { ILayerZeroEndpoint } from "../interfaces/adapters/ILayerZeroEndpoint.sol";
import { ILayerZeroUserApplicationConfig } from "../interfaces/adapters/ILayerZeroUserApplicationConfig.sol";
import { IPostman } from "../interfaces/xChain/IPostman.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { XChainIntegrator } from "./XChainIntegrator.sol";
import "../interfaces/MsgStructs.sol";

// import "hardhat/console.sol";

struct chainPair {
	uint16 from;
	uint16 to;
}

contract LayerZeroPostman is
	ILayerZeroReceiver,
	ILayerZeroUserApplicationConfig,
	IPostman,
	Ownable
{
	ILayerZeroEndpoint public endpoint;
	address public refundTo;

	// map original chainIds to layerZero's chainIds
	mapping(uint16 => uint16) public chains;

	constructor(
		address _layerZeroEndpoint,
		chainPair[] memory chainPairArr,
		address _refundTo
	) {
		endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
		refundTo = _refundTo;

		uint256 length = chainPairArr.length;
		for (uint256 i; i < length; ) {
			chainPair memory pair = chainPairArr[i];
			chains[pair.from] = pair.to;

			unchecked {
				++i;
			}
		}
	}

	/*/////////////////////////////////////////////////////
					Messaging Logic
	/////////////////////////////////////////////////////*/

	function deliverMessage(
		Message calldata _msg,
		address _dstVaultAddress,
		address _dstPostman,
		MessageType _messageType,
		uint16 _dstChainId
	) external payable override {
		if (address(this).balance == 0) revert NoBalance();

		Message memory msgToLayerZero = Message({
			value: _msg.value,
			sender: msg.sender,
			client: _msg.client,
			chainId: _msg.chainId
		});

		bytes memory adapterParams = _getAdapterParams();
		bytes memory payload = abi.encode(msgToLayerZero, _dstVaultAddress, _messageType);

		endpoint.send{ value: msg.value }(
			uint16(chains[_dstChainId]),
			abi.encodePacked(_dstPostman, address(this)),
			payload,
			payable(refundTo),
			address(0x0),
			adapterParams
		);
	}

	function lzReceive(
		uint16,
		bytes memory,
		uint64,
		bytes memory _payload
	) external override {
		if (msg.sender != address(endpoint)) revert Unauthorized();

		(Message memory _msg, address _dstVaultAddress, uint16 _messageType) = abi.decode(
			_payload,
			(Message, address, uint16)
		);

		emit MessageReceived(_msg.sender, _msg.value, _dstVaultAddress, _messageType, _msg.chainId);

		XChainIntegrator(_dstVaultAddress).receiveMessage(_msg, MessageType(_messageType));
	}

	/*/////////////////////////////////////////////////////
					UTILS
	/////////////////////////////////////////////////////*/

	function _getAdapterParams() internal pure returns (bytes memory) {
		uint16 version = 1;
		uint256 gasForDestinationLzReceive = 350000;
		return abi.encodePacked(version, gasForDestinationLzReceive);
	}

	function estimateFee(
		uint16 _dstChainId,
		address _dstVaultAddress,
		MessageType _messageType,
		Message calldata _msg
	) external view returns (uint256) {
		return _estimateFee(_dstChainId, _dstVaultAddress, _messageType, _msg);
	}

	function _estimateFee(
		uint16 _dstChainId,
		address _dstVaultAddress,
		MessageType _messageType,
		Message calldata _msg
	) internal view returns (uint256) {
		Message memory msgToLayerZero = Message({
			value: _msg.value,
			sender: msg.sender,
			client: _msg.client,
			chainId: _msg.chainId
		});

		bytes memory payload = abi.encode(msgToLayerZero, _dstVaultAddress, _messageType);
		bytes memory adapterParams = _getAdapterParams();

		(uint256 messageFee, ) = endpoint.estimateFees(
			uint16(chains[_dstChainId]),
			address(this),
			payload,
			false,
			adapterParams
		);

		return messageFee;
	}

	/*/////////////////////////////////////////////////////
					CONFIG
	/////////////////////////////////////////////////////*/

	function setRefundTo(address _refundTo) external onlyOwner {
		refundTo = _refundTo;
	}

	function setChain(uint16 _chainId, uint16 _lzChainId) external onlyOwner {
		chains[_chainId] = _lzChainId;
	}

	function setConfig(
		uint16,
		uint16 _dstChainId,
		uint256 _configType,
		bytes memory _config
	) external override onlyOwner {
		endpoint.setConfig(
			chains[_dstChainId],
			endpoint.getSendVersion(address(this)),
			_configType,
			_config
		);
	}

	function getConfig(
		uint16,
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

	function setSendVersion(uint16 version) external override onlyOwner {
		endpoint.setSendVersion(version);
	}

	function setReceiveVersion(uint16 version) external override onlyOwner {
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

	function fundPostman() external payable override {}

	/*/////////////////////////////////////////////////////
					EVENTS
	/////////////////////////////////////////////////////*/
	event MessageReceived(
		address srcVaultAddress,
		uint256 amount,
		address dstVaultAddress,
		uint16 messageType,
		uint256 srcChainId
	);

	/*/////////////////////////////////////////////////////
					ERRORS
	/////////////////////////////////////////////////////*/
	error Unauthorized();
	error NoBalance();
}
