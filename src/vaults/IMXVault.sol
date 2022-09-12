// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { IMXStrategy, Strategy } from "./adapters/IMXStrategy.sol";
import { SCYVault } from "./scy/SCYVault.sol";

contract IMXVault is IMXStrategy, SCYVault {
	constructor() {}
}
