// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.16;

// import { SCYStrategy } from "../../vaults/ERC5115/SCYStrategy.sol";
// import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { SCYVaultU } from "../../vaults/ERC5115/SCYVaultU.sol";
// import { AuthConfig } from "../../common/Auth.sol";
// import { FeeConfig } from "../../common/Fees.sol";
// import { HarvestSwapParams } from "../../interfaces/Structs.sol";
// import { ISCYStrategy } from "../../interfaces/ERC5115/ISCYStrategy.sol";
// import { SCYVaultConfig } from "../../interfaces/ERC5115/ISCYVault.sol";

// // import "hardhat/console.sol";

// contract SynapseVaultU is SCYStrategy, SCYVaultU {
// 	using SafeERC20 for IERC20;

// 	function initialize(
// 		AuthConfig memory authConfig,
// 		FeeConfig memory feeConfig,
// 		SCYVaultConfig memory vaultConfig
// 	) external initializer {
// 		__Auth_init(authConfig);
// 		__Fees_init(feeConfig);
// 		__SCYVault_init(vaultConfig);
// 	}

// 	// False by default
// 	function sendERC20ToStrategy() public pure override returns (bool) {
// 		return true;
// 	}

// 	function _stratValidate() internal view override {
// 		// TODO check that yield token == strategy lpToken (or collateralToken)
// 		if (underlying != ISCYStrategy(strategy).underlying()) revert InvalidStrategy();
// 	}

// 	function _stratDeposit(uint256 amount) internal override returns (uint256) {
// 		return ISCYStrategy(strategy).deposit(amount);
// 	}

// 	function _stratRedeem(address recipient, uint256 amount)
// 		internal
// 		override
// 		returns (uint256 amountOut, uint256 amntToTransfer)
// 	{
// 		// funds are sent directly to recipient
// 		amountOut = ISCYStrategy(strategy).redeem(recipient, amount);
// 		// need this check of Native Tokens
// 		if (recipient == address(this)) amntToTransfer = amountOut;
// 		else amntToTransfer = 0;
// 		return (amountOut, amntToTransfer);
// 	}

// 	function _stratGetAndUpdateTvl() internal override returns (uint256) {
// 		return ISCYStrategy(strategy).getAndUpdateTvl();
// 	}

// 	function _strategyTvl() internal view override returns (uint256) {
// 		return ISCYStrategy(strategy).getTvl();
// 	}

// 	function _stratClosePosition(uint256 slippage) internal override returns (uint256) {
// 		return ISCYStrategy(strategy).closePosition(slippage);
// 	}

// 	function _stratMaxTvl() internal view override returns (uint256) {
// 		return ISCYStrategy(strategy).getMaxTvl();
// 	}

// 	function _stratCollateralToUnderlying() internal view override returns (uint256) {
// 		return ISCYStrategy(strategy).collateralToUnderlying();
// 	}

// 	function _selfBalance(address token) internal view override returns (uint256) {
// 		if (token == address(yieldToken)) return ISCYStrategy(strategy).getTokenBalance(yieldToken);
// 		return (token == NATIVE) ? address(this).balance : IERC20(token).balanceOf(address(this));
// 	}

// 	function _stratHarvest(
// 		HarvestSwapParams[] calldata farm1Params,
// 		HarvestSwapParams[] calldata farm2Params
// 	) internal override returns (uint256[] memory harvested1, uint256[] memory harvested2) {
// 		return ISCYStrategy(strategy).harvest(farm1Params, farm2Params);
// 	}

// 	function getWithdrawAmnt(uint256 shares) public view override returns (uint256) {
// 		uint256 assets = convertToAssets(shares);
// 		return ISCYStrategy(strategy).getWithdrawAmnt(assets);
// 	}

// 	function getDepositAmnt(uint256 uAmnt) public view override returns (uint256) {
// 		uint256 assets = ISCYStrategy(strategy).getDepositAmnt(uAmnt);
// 		return convertToShares(assets);
// 	}
// }
