// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMasterChef } from "../../interfaces/uniswap/IStakingRewards.sol";
import { IUniswapV2Pair } from "../../interfaces/uniswap/IUniswapV2Pair.sol";

import { IUniswapV2Router01 } from "../../interfaces/uniswap/IUniswapV2Router01.sol";
import { IUniFarm, HarvestSwapParams } from "../mixins/IUniFarm.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

abstract contract MasterChefFarm is IUniFarm {
	using SafeERC20 for IERC20;

	IMasterChef private _farm;
	IUniswapV2Router01 private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;

	constructor(
		address pair_,
		address farm_,
		address router_,
		address farmToken_,
		uint256 farmPid_
	) {
		_farm = IMasterChef(farm_);
		_router = IUniswapV2Router01(router_);
		_farmToken = IERC20(farmToken_);
		_pair = IUniswapV2Pair(pair_);
		_farmId = farmPid_;
		_addFarmApprovals();
	}

	// assumption that _router and _farm are trusted
	function _addFarmApprovals() internal override {
		IERC20(address(_pair)).safeIncreaseAllowance(address(_farm), type(uint256).max);
		if (_farmToken.allowance(address(this), address(_router)) == 0)
			_farmToken.safeIncreaseAllowance(address(_router), type(uint256).max);
	}

	function farmRouter() public view override returns (address) {
		return address(_router);
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return _pair;
	}

	function _withdrawFromFarm(uint256 amount) internal override {
		_farm.withdraw(_farmId, amount);
	}

	function _depositIntoFarm(uint256 amount) internal override {
		_farm.deposit(_farmId, amount);
	}

	function _harvestFarm(HarvestSwapParams[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		_farm.deposit(_farmId, 0);
		uint256 farmHarvest = _farmToken.balanceOf(address(this));
		if (farmHarvest == 0) return harvested;

		HarvestSwapParams memory swapParam = swapParams[0];
		_validatePath(address(_farmToken), swapParam.path);

		uint256[] memory amounts = _router.swapExactTokensForTokens(
			farmHarvest,
			swapParam.min,
			swapParam.path, // optimal route determined externally
			address(this),
			swapParam.deadline
		);

		harvested = new uint256[](1);
		harvested[0] = amounts[amounts.length - 1];
		emit HarvestedToken(address(_farmToken), harvested[0]);

		// additional chain token rewards
		uint256 nativeBalance = address(this).balance;
		if (nativeBalance > 0) {
			IWETH(address(short())).deposit{ value: nativeBalance }();
			emit HarvestedToken(address(short()), nativeBalance);
		}
	}

	function _getFarmLp() internal view override returns (uint256) {
		(uint256 lp, ) = _farm.userInfo(_farmId, address(this));
		return lp;
	}

	function _getLiquidity(uint256 lpTokenBalance) internal view override returns (uint256) {
		uint256 farmLp = _getFarmLp();
		return farmLp + lpTokenBalance;
	}

	function _getLiquidity() internal view override returns (uint256) {
		uint256 farmLp = _getFarmLp();
		uint256 poolLp = _pair.balanceOf(address(this));
		return farmLp + poolLp;
	}
}
