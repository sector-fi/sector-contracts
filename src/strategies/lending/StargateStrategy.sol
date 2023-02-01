// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { HarvestSwapParams } from "../../interfaces/Structs.sol";
import { IStargateRouter, lzTxObj } from "../../interfaces/stargate/IStargateRouter.sol";
import { IStargatePool } from "../../interfaces/stargate/IStargatePool.sol";
import { StarChefFarm, FarmConfig } from "../../strategies/adapters/StarChefFarm.sol";
import { StratAuthLight } from "../../common/StratAuthLight.sol";

// import "hardhat/console.sol";

// This strategy assumes that sharedDecimans and localDecimals are the same
contract StargateStrategy is StarChefFarm, StratAuthLight {
	using SafeERC20 for IERC20;

	IStargatePool public stargatePool;
	IStargateRouter public stargateRouter;
	IERC20 public underlying;
	uint16 pId;

	constructor(
		address _vault,
		address _stargatePool,
		address _stargateRouter,
		uint16 _pId,
		FarmConfig memory _farmConfig
	) StarChefFarm(_farmConfig) {
		vault = _vault;
		pId = _pId;
		stargatePool = IStargatePool(_stargatePool);
		stargateRouter = IStargateRouter(_stargateRouter);
		underlying.safeApprove(_stargateRouter, type(uint256).max);
		IERC20(stargatePool).safeApprove(address(farm), type(uint256).max);
	}

	function deposit(uint256 amount) public onlyVault returns (uint256) {
		uint256 lp = (amount * 1e18) / stargatePool.amountLPtoLD(1e18);
		stargateRouter.addLiquidity(pId, amount, address(this));
		_depositIntoFarm(lp);
		return lp;
	}

	function redeem(address to, uint256 amount) public onlyVault returns (uint256 amountOut) {
		_withdrawFromFarm(amount);
		amountOut = stargateRouter.instantRedeemLocal(pId, amount, to);
		underlying.safeTransfer(to, amountOut);
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

	function getTvl() public view returns (uint256) {
		(uint256 balance, ) = farm.userInfo(uint256(farmId), address(this));
		return IStargatePool(stargatePool).amountLPtoLD(balance);
	}

	function closePosition() public onlyVault returns (uint256) {
		(uint256 balance, ) = farm.userInfo(farmId, address(this));
		_withdrawFromFarm(balance);
		return stargateRouter.instantRedeemLocal(pId, balance, address(this));
	}

	function maxTvl() external view returns (uint256) {
		return IERC20(stargatePool).totalSupply() / 10; // 10% of total deposits
	}

	function collateralToUnderlying() external view returns (uint256) {
		return IStargatePool(stargatePool).amountLPtoLD(1e18);
	}

	function getFarmLp() public view returns (uint256) {
		return _getFarmLp();
	}

	// EMERGENCY GUARDIAN METHODS
	function redeemRemote(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress,
		uint256 _amountLP,
		uint256 _minAmountLD,
		bytes calldata _to,
		lzTxObj memory _lzTxParams
	) external payable onlyVault {
		stargateRouter.redeemRemote(
			_dstChainId,
			_srcPoolId,
			_dstPoolId,
			_refundAddress,
			_amountLP,
			_minAmountLD,
			_to,
			_lzTxParams
		);
	}

	function redeemLocal(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress,
		uint256 _amountLP,
		bytes calldata _to,
		lzTxObj memory _lzTxParams
	) external payable onlyVault {
		stargateRouter.redeemLocal(
			_dstChainId,
			_srcPoolId,
			_dstPoolId,
			_refundAddress,
			_amountLP,
			_to,
			_lzTxParams
		);
	}

	function sendCredits(
		uint16 _dstChainId,
		uint256 _srcPoolId,
		uint256 _dstPoolId,
		address payable _refundAddress
	) external payable onlyVault {
		stargateRouter.sendCredits(_dstChainId, _srcPoolId, _dstPoolId, _refundAddress);
	}
}
