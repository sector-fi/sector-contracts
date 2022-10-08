// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;
import { Message } from "../MsgStructs.sol";

interface IPostman {
	function deliverMessage(
		Message calldata _msg,
		address _dstVautAddress,
		address _dstPostman,
		uint16 _messageType,
        uint16 _srcChainId
	) external;
}