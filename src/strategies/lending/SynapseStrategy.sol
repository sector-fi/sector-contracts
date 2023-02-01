// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IStargateRouter } from "../../interfaces/stargate/IStargateRouter.sol";
import { ISynapseSwap } from "../../interfaces/synapse/ISynapseSwap.sol";
import { MiniChef2Farm, FarmConfig } from "../../strategies/adapters/MiniChef2Farm.sol";

// import "hardhat/console.sol";

// This synapsePool assumes that sharedDecimans and localDecimals are the same
contract SynapseStrategy is MiniChef2Farm {
	using SafeERC20 for IERC20;

	uint256 public _nTokens;
	address public vault;
	ISynapseSwap public synapsePool;
	IERC20 public lpToken;
	IERC20 public underlying;
	uint8 public coinId;

	modifier onlyVault() {
		require(msg.sender == vault, "Only vault");
		_;
	}

	constructor(
		address _vault,
		address _synapsePool,
		address _lpToken,
		FarmConfig memory _farmConfig
	) MiniChef2Farm(_farmConfig) {
		vault = _vault;
		synapsePool = ISynapseSwap(_synapsePool);
		lpToken = IERC20(_lpToken);
		underlying = synapsePool.getToken(coinId);
		underlying.safeApprove(_synapsePool, type(uint256).max);
		IERC20(lpToken).safeApprove(address(farm), type(uint256).max);
		IERC20(lpToken).safeApprove(_synapsePool, type(uint256).max);
		_nTokens = ISynapseSwap(synapsePool).calculateRemoveLiquidity(1).length;
	}

	function deposit(uint256 amount) public onlyVault returns (uint256) {
		uint256[] memory amounts = new uint256[](_nTokens);
		amounts[coinId] = amount;
		// min LP tokens is checked in redeem method
		uint256 lp = ISynapseSwap(synapsePool).addLiquidity(amounts, 0, block.timestamp);
		_depositIntoFarm(lp);
		return lp;
	}

	function redeem(address recipient, uint256 amount)
		external
		onlyVault
		returns (uint256 amountOut)
	{
		_withdrawFromFarm(amount);
		amountOut = ISynapseSwap(synapsePool).removeLiquidityOneToken(
			amount,
			coinId,
			0,
			block.timestamp
		);
		underlying.safeTransfer(recipient, amountOut);
	}

	function getTvl() public view returns (uint256) {
		(uint256 balance, ) = farm.userInfo(uint256(farmId), address(this));
		if (balance == 0) return 0;
		return ISynapseSwap(synapsePool).calculateRemoveLiquidityOneToken(balance, coinId);
	}

	function closePosition() external onlyVault returns (uint256 amountOut) {
		(uint256 balance, ) = farm.userInfo(farmId, address(this));
		_withdrawFromFarm(balance);
		amountOut = ISynapseSwap(synapsePool).removeLiquidityOneToken(
			balance,
			coinId,
			0,
			block.timestamp
		);
		underlying.safeTransfer(address(vault), amountOut);
	}

	function maxTvl() external view returns (uint256) {
		return IERC20(lpToken).totalSupply() / 10; // 10% of total deposits
	}

	function collateralToUnderlying() external view returns (uint256) {
		return ISynapseSwap(synapsePool).calculateRemoveLiquidityOneToken(1e18, coinId);
	}

	function harvest(HarvestSwapParams[] calldata params)
		external
		onlyVault
		returns (uint256[] memory harvested)
	{
		uint256 amountOut = _harvestFarm(params[0]);
		if (amountOut > 0) deposit(amountOut);
		harvested = new uint256[](1);
		harvested[0] = amountOut;
	}

	function getWithdrawAmnt(uint256 lpTokens) public view returns (uint256) {
		return ISynapseSwap(synapsePool).calculateRemoveLiquidityOneToken(lpTokens, coinId);
	}

	function getDepositAmnt(uint256 uAmnt) public view returns (uint256) {
		uint256[] memory amounts = new uint256[](_nTokens);
		amounts[coinId] = uAmnt;
		return ISynapseSwap(synapsePool).calculateTokenAmount(amounts, true);
	}

	function getTokenBalance(address token) public view returns (uint256) {
		if (token == address(lpToken)) return _getFarmLp();
		return IERC20(token).balanceOf(address(this));
	}
}