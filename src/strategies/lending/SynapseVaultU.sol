// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SCYStrategy, Strategy } from "../../vaults/ERC5115/SCYStrategy.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SCYVaultU } from "../../vaults/ERC5115/SCYVaultU.sol";
import { AuthConfig } from "../../common/Auth.sol";
import { FeeConfig } from "../../common/Fees.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { SynapseStrategy } from "./SynapseStrategy.sol";

// import "hardhat/console.sol";

contract SynapseVaultU is SCYStrategy, SCYVaultU {
	using SafeERC20 for IERC20;

	function initialize(
		AuthConfig memory authConfig,
		FeeConfig memory feeConfig,
		Strategy memory _strategy
	) external initializer {
		__Auth_init(authConfig);
		__Fees_init(feeConfig);
		__SCYVault_init(_strategy);
	}

	// False by default
	function sendERC20ToStrategy() public pure override returns (bool) {
		return true;
	}

	function _stratValidate() internal view override {
		if (underlying != SynapseStrategy(strategy).underlying()) revert InvalidStrategy();
	}

	function _stratDeposit(uint256 amount) internal override returns (uint256) {
		return SynapseStrategy(strategy).deposit(amount);
	}

	function _stratRedeem(address recipient, uint256 amount)
		internal
		override
		returns (uint256 amountOut, uint256 amntToTransfer)
	{
		// funds sent directly to recipient
		amountOut = SynapseStrategy(strategy).redeem(recipient, amount);
		return (amountOut, amntToTransfer);
	}

	function _stratGetAndUpdateTvl() internal view override returns (uint256) {
		return SynapseStrategy(strategy).getTvl();
	}

	function _strategyTvl() internal view override returns (uint256) {
		return SynapseStrategy(strategy).getTvl();
	}

	function _stratClosePosition(uint256) internal override returns (uint256) {
		return SynapseStrategy(strategy).closePosition();
	}

	function _stratMaxTvl() internal view override returns (uint256) {
		return SynapseStrategy(strategy).maxTvl();
	}

	function _stratCollateralToUnderlying() internal view override returns (uint256) {
		return SynapseStrategy(strategy).collateralToUnderlying();
	}

	function _selfBalance(address token) internal view override returns (uint256) {
		if (token == address(yieldToken))
			return SynapseStrategy(strategy).getTokenBalance(yieldToken);
		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
	}

	function _stratHarvest(HarvestSwapParams[] calldata farm1Params, HarvestSwapParams[] calldata)
		internal
		override
		returns (uint256[] memory harvested, uint256[] memory)
	{
		harvested = SynapseStrategy(strategy).harvest(farm1Params);
		return (harvested, new uint256[](0));
	}

	function getWithdrawAmnt(uint256 shares) public view override returns (uint256) {
		uint256 assets = convertToAssets(shares);
		return SynapseStrategy(strategy).getWithdrawAmnt(assets);
	}

	function getDepositAmnt(uint256 uAmnt) public view override returns (uint256) {
		uint256 assets = SynapseStrategy(strategy).getDepositAmnt(uAmnt);
		return convertToShares(assets);
	}
}