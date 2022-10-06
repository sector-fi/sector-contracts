// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ILayerZeroReceiver } from "../interfaces/adapters/ILayerZeroReceiver.sol";
import { ILayerZeroEndpoint } from "../interfaces/adapters/ILayerZeroEndpoint.sol";
import { ILayerZeroUserApplicationConfig } from "../interfaces/adapters/ILayerZeroUserApplicationConfig.sol";
import { XAdapter } from "./XAdapter.sol";
import { Auth } from "../common/Auth.sol";

contract LayerZeroAdapter is ILayerZeroReceiver, ILayerZeroUserApplicationConfig, XAdapter, Auth {
	ILayerZeroEndpoint public endpoint;

	struct lzConfig {
		address adapter;
		uint16 lzChainId;
	}

	struct message {
		uint256 deposits;
		uint256 withdrawals;
		uint256 redeemed;
	}

	mapping(uint256 => mapping(address => message)) messages;

	mapping(uint256 => lzConfig) chains;

	constructor(
		address _layerZeroEndpoint,
		address _owner,
		address _guardian,
		address _manager
	) Auth(_owner, _guardian, _manager) {
		endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
	}

	function sendMessage(
		uint256 _amount,
		address _dstVautAddress,
		address _srcVautAddress,
		uint256 _dstChainId,
		uint16 _messageType,
		uint256 _srcChainId
	) external override onlyRole(MANAGER) {
		_srcChainId;
		if (address(this).balance == 0) revert NoBalance();

		bytes memory payload = abi.encode(_amount, _srcVautAddress, _dstVautAddress, _messageType);

		// encode adapterParams to specify more gas for the destination
		uint16 version = 1;
		uint256 gasForDestinationLzReceive = 350000;
		bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);
		(uint256 messageFee, ) = endpoint.estimateFees(
			uint16(chains[_dstChainId].lzChainId),
			address(this),
			payload,
			false,
			adapterParams
		);
		if (address(this).balance < messageFee) revert InsufficientBalanceToSendMessage();

		// send LayerZero message
		endpoint.send{ value: messageFee }( // {value: messageFee} will be paid out of this contract!
			uint16(chains[_dstChainId].lzChainId), // destination chainId
			abi.encodePacked(chains[_dstChainId].adapter), // destination address of Adapter on dst chain
			payload, // abi.encode()'ed bytes
			payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
			address(0x0), // 'zroPaymentAddress' unused for this mock/example
			adapterParams // 'adapterParams' unused for this mock/example
		);
	}

	function lzReceive(
		uint16 _srcChainId,
		bytes memory _fromAddress,
		uint64, /*_nonce*/
		bytes memory _payload
	) external override {
		// lzReceive can only be called by the LayerZero endpoint
		if (msg.sender != address(endpoint)) revert Unauthorized();

		// use assembly to extract the address from the bytes memory parameter
		address fromAddress;
		assembly {
			fromAddress := mload(add(_fromAddress, 20))
		}

		// decode payload sent from source chain
		(
			uint256 _amount,
			address _srcVaultAddress,
			address _dstVaultAddress,
			uint16 messageType
		) = abi.decode(_payload, (uint256, address, address, uint16));

		// TODO: Implement storage logic for differente message types.
		// deposit has messageType === 1
		// redeemRequest has messageType === 2
		// redeem has messageType === 3

		emit MessageReceived(
			_srcChainId,
			fromAddress,
			_srcVaultAddress,
			_amount,
			_dstVaultAddress,
			messageType
		);
	}

	function setChain(
		uint256 _chainId,
		address _adapter,
		uint16 _lzChainId
	) external onlyRole(MANAGER) {
		chains[_chainId].adapter = _adapter;
		chains[_chainId].lzChainId = _lzChainId;
	}

	function setConfig(
		uint16,
		uint16 _dstChainId,
		uint256 _configType,
		bytes memory _config
	) external override {
		endpoint.setConfig(
			chains[_dstChainId].lzChainId,
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
	event MessageReceived(
		uint16 _srcChainId,
		address fromAddress,
		address destAddress,
		uint256 amount,
		address srcAddress,
		uint16 messageType
	);

	/* ERRORS */
	error Unauthorized();
	error NoBalance();
	error InsufficientBalanceToSendMessage();
}
