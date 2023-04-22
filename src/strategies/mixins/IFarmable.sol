// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IBase, HarvestSwapParams } from "./IBase.sol";

abstract contract IFarmable is IBase {
	event HarvestedToken(address indexed token, uint256 amount);

	function _validatePath(address farmToken, address[] memory path) internal view {
		address out = path[path.length - 1];
		// ensure malicious harvester is not trading with wrong tokens
		// TODO should we add more validation to prevent malicious path?
		require(
			((path[0] == address(farmToken) && (out == address(short()))) ||
				out == address(underlying())),
			"BAD_PATH"
		);
	}
}
