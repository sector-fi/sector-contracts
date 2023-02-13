// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { HLPConfig, NativeToken } from "../../interfaces/Structs.sol";
import { HLPCore, IBase, IERC20 } from "./HLPCore.sol";
import { Compound } from "../adapters/Compound.sol";
import { MasterChefFarm } from "../adapters/MasterChefFarm.sol";
import { CompMultiFarm, CompoundFarm } from "../adapters/CompMultiFarm.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";

// import "hardhat/console.sol";

// USED BY:
// USDCmovrSOLARwell
contract MasterChefCompMulti is HLPCore, Compound, CompMultiFarm, MasterChefFarm {
	// HedgedLP should allways be intialized last
	constructor(AuthConfig memory authConfig, HLPConfig memory config)
		Auth(authConfig)
		MasterChefFarm(
			config.uniPair,
			config.uniFarm,
			config.farmRouter,
			config.farmToken,
			config.farmId
		)
		Compound(config.comptroller, config.cTokenLend, config.cTokenBorrow)
		CompoundFarm(config.lendRewardRouter, config.lendRewardToken)
		HLPCore(config.underlying, config.short, config.vault)
	{
		nativeToken = config.nativeToken;
	}

	function underlying() public view override(IBase, HLPCore) returns (IERC20) {
		return super.underlying();
	}
}
