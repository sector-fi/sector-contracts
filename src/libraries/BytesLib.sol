// SPDX-License-Identifier: GPL-2.0
/*
 * @title Solidity Bytes Arrays Utils
 * @author Gonçalo Sá <goncalo.sa@consensys.net>
 *
 * @dev Bytes tightly packed arrays utility library for ethereum contracts written in Solidity.
 *      The library lets you concatenate, slice and type cast bytes arrays both in memory and storage.
 */
pragma solidity 0.8.16;

library BytesLib {
	function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address) {
		require(_start + 20 >= _start, "toAddress_overflow");
		require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
		address tempAddress;

		assembly {
			tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
		}

		return tempAddress;
	}

	function fromLast20Bytes(bytes32 bytesValue) internal pure returns (address) {
		return address(uint160(uint256(bytesValue)));
	}

	function fillLast12Bytes(address addressValue) internal pure returns (bytes32) {
		return bytes32(bytes20(addressValue));
	}
}
