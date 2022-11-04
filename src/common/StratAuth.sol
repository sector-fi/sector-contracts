// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Auth } from "./Auth.sol";
import { EAction } from "../interfaces/Structs.sol";

// import "hardhat/console.sol";

abstract contract StratAuth is Auth {
	address public vault;

	modifier onlyVault() {
		require(msg.sender == vault, "Strat: ONLY_VAULT");
		_;
	}

	event EmergencyAction(address indexed target, bytes data);

	/// @notice calls arbitrary function on target contract in case of emergency
	function emergencyAction(EAction[] calldata actions) public onlyOwner {
		uint256 l = actions.length;
		for (uint256 i = 0; i < l; i++) {
			address target = actions[i].target;
			bytes memory data = actions[i].data;
			(bool success, ) = target.call{ value: actions[i].value }(data);
			require(success, "emergencyAction failed");
			emit EmergencyAction(target, data);
		}
	}
}
