// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { OwnableTransfer, Ownable } from "./common/OwnableTransfer.sol";

contract SectorBeacon is UpgradeableBeacon, OwnableTransfer {
	constructor(address _implementation) UpgradeableBeacon(_implementation) {}

	function transferOwnership(address _pendingOwner) public override(Ownable, OwnableTransfer) {
		super.transferOwnership(_pendingOwner);
	}
}
