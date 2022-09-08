// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IMXCore } from "./IMXCore.sol";
import { IMXFarm } from "./IMXFarm.sol";
import { IMXConfig } from "../../interfaces/Structs.sol";

// import "hardhat/console.sol";

contract IMX is IMXCore, IMXFarm {
	function initialize(IMXConfig memory config) public initializer {
		__Auth_init_(config.owner, config.guardian, config.manager);

		__IMXFarm_init_(
			config.underlying,
			config.uniPair,
			config.poolToken,
			config.farmRouter,
			config.farmToken
		);

		// HedgedLP should allways be intialized last
		__IMX_init_(config.vault, config.underlying, config.short, config.maxTvl);
	}
}
