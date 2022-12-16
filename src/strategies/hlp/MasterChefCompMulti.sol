// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { HLPConfig, NativeToken } from "../../interfaces/Structs.sol";
import { HLPCore } from "./HLPCore.sol";
import { Compound } from "../adapters/Compound.sol";
import { MasterChefFarm } from "../adapters/MasterChefFarm.sol";
import { CompMultiFarm } from "../adapters/CompMultiFarm.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";

// import "hardhat/console.sol";

// USED BY:
// USDCmovrSOLARwell
contract MasterChefCompMulti is HLPCore, Compound, CompMultiFarm, MasterChefFarm {
	// HedgedLP should allways be intialized last
	constructor(AuthConfig memory authConfig, HLPConfig memory config) Auth(authConfig) {
		__MasterChefFarm_init_(
			config.uniPair,
			config.uniFarm,
			config.farmRouter,
			config.farmToken,
			config.farmId
		);

		__Compound_init_(config.comptroller, config.cTokenLend, config.cTokenBorrow);

		__CompoundFarm_init_(config.lendRewardRouter, config.lendRewardToken);

		__HedgedLP_init_(config.underlying, config.short, config.vault);

		nativeToken = config.nativeToken;
	}
}
