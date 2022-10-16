// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { Test } from "forge-std/Test.sol";

contract SectorTest is Test {
	address manager = address(101);
	address guardian = address(102);
	address treasury = address(103);
	address owner = address(this);

	address user1 = address(201);
	// 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
	address user2 = address(202);
	// 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
	address user3 = address(203);
}
