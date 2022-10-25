// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IMasterChef } from "../../../interfaces/uniswap/IStakingRewards.sol";
import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";

import { IUniFarm, IUniswapV2Router01, HarvestSwapParams } from "../../mixins/IUniFarm.sol";
import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

abstract contract MasterChefFarm is IUniFarm {
	using SafeERC20 for IERC20;

	IMasterChef private _farm;
	IUniswapV2Router01 private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;

	function __MasterChefFarm_init_(
		address pair_,
		address farm_,
		address router_,
		address farmToken_,
		uint256 farmPid_
	) internal initializer {
		_farm = IMasterChef(farm_);
		_router = IUniswapV2Router01(router_);
		_farmToken = IERC20(farmToken_);
		_pair = IUniswapV2Pair(pair_);
		_farmId = farmPid_;
	}

	// assumption that _router and _farm are trusted
	function _addFarmApprovals() internal override {
		IERC20(address(_pair)).safeApprove(address(_farm), type(uint256).max);
		if (_farmToken.allowance(address(this), address(_router)) == 0)
			_farmToken.safeApprove(address(_router), type(uint256).max);
	}

	function farmRouter() public view override returns (IUniswapV2Router01) {
		return _router;
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
		address[] memory addresses;
		uint256[] memory amounts;

		_farm.deposit(_farmId, 0);
		harvested = new uint256[](1);
		harvested[0] = _farmToken.balanceOf(address(this));
		if (harvested[0] == 0) return harvested;

		_swap(_router, swapParams[0], address(_farmToken), harvested[0]);
		emit HarvestedToken(address(_farmToken), harvested[0]);

		// additional chain token rewards
		uint256 ethBalance = address(this).balance;
		if (ethBalance > 0) {
			IWETH(address(short())).deposit{ value: ethBalance }();
			emit HarvestedToken(address(short()), ethBalance);
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
