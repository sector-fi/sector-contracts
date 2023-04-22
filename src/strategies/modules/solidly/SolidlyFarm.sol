// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISolidlyGauge } from "./interfaces/ISolidlyGauge.sol";
import { ISolidlyRouter } from "./interfaces/ISolidlyRouter.sol";

import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";

import { IUniFarm, HarvestSwapParams } from "../../mixins/IUniFarm.sol";
import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

abstract contract SolidlyFarm is IUniFarm {
	using SafeERC20 for IERC20;

	ISolidlyGauge private _farm;
	ISolidlyRouter private _router;
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
		_farm = ISolidlyGauge(farm_);
		_router = ISolidlyRouter(router_);
		_farmToken = IERC20(farmToken_);
		_pair = IUniswapV2Pair(pair_);
		_farmId = farmPid_;
		_addFarmApprovals();
	}

	// assumption that _router and _farm are trusted
	function _addFarmApprovals() internal override {
		IERC20(address(_pair)).safeApprove(address(_farm), type(uint256).max);
		if (_farmToken.allowance(address(this), address(_router)) == 0)
			_farmToken.safeApprove(address(_router), type(uint256).max);
	}

	function farmRouter() public view override returns (address) {
		return address(_router);
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return _pair;
	}

	function _withdrawFromFarm(uint256 amount) internal override {
		_farm.withdraw(amount);
	}

	function _depositIntoFarm(uint256 amount) internal override {
		_farm.deposit(amount, 0);
	}

	function _harvestFarm(HarvestSwapParams[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		address[] memory tokens = new address[](1);
		tokens[0] = address(_farmToken);
		_farm.getReward(address(this), tokens);
		uint256 farmHarvest = _farmToken.balanceOf(address(this));
		if (farmHarvest == 0) return harvested;

		_validatePath(address(_farmToken), swapParams[0].path);

		HarvestSwapParams memory swapParam = swapParams[0];
		uint256 l = swapParam.path.length;
		ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](l - 1);
		for (uint256 i = 0; i < l - 1; i++) {
			routes[i] = (ISolidlyRouter.route(swapParam.path[i], swapParam.path[i + 1], false));
		}

		uint256[] memory amounts = _router.swapExactTokensForTokens(
			farmHarvest,
			swapParam.min,
			routes,
			address(this),
			block.timestamp
		);

		harvested = new uint256[](1);
		harvested[0] = amounts[amounts.length - 1];
		emit HarvestedToken(address(_farmToken), harvested[0]);
	}

	function _getFarmLp() internal view override returns (uint256) {
		uint256 lp = _farm.balanceOf(address(this));
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
