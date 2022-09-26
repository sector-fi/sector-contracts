// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IVirtualToken {
	function isInWhitelist(address account) external view returns (bool);
}
