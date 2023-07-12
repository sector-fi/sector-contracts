// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { HLPConfig } from "../../interfaces/Structs.sol";
import { HLPCore, IBase, IERC20 } from "./HLPCore.sol";
import { AaveModule } from "../modules/aave/AaveModule.sol";
import { AaveFarm } from "../modules/aave/AaveFarm.sol";
import { VeloV2Farm } from "../modules/solidly/VeloV2Farm.sol";
import { Auth, AuthConfig } from "../../common/Auth.sol";

// import "hardhat/console.sol";

/// @title SolidlyAave
/// @notice HLP Strategy using Solidly exchange and Aaave money market
contract VeloV2Aave is HLPCore, AaveModule, AaveFarm, VeloV2Farm {
	// HLPCore should  be intialized last
	constructor(AuthConfig memory authConfig, HLPConfig memory config)
		Auth(authConfig)
		VeloV2Farm(
			config.uniPair,
			config.uniFarm,
			config.farmRouter,
			config.farmToken,
			config.farmId
		)
		AaveModule(config.comptroller, config.cTokenLend, config.cTokenBorrow)
		AaveFarm(config.lendRewardRouter, config.lendRewardToken)
		HLPCore(config.underlying, config.short, config.vault)
	{}

	function underlying() public view override(IBase, HLPCore) returns (IERC20) {
		return super.underlying();
	}
}
