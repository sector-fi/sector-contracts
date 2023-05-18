// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { INFTPool } from "./interfaces/INFTPool.sol";
import { ICamelotMaster } from "./interfaces/ICamelotMaster.sol";
import { ICamelotRouter } from "./interfaces/ICamelotRouter.sol";
import { INFTHandler } from "./interfaces/INFTHandler.sol";
import { ISectGrail } from "./interfaces/ISectGrail.sol";

import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";

import { IUniFarm, HarvestSwapParams } from "../../mixins/IUniFarm.sol";
import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";
import { StratAuth } from "../../../common/StratAuth.sol";

// import "hardhat/console.sol";

abstract contract CamelotSectGrailFarm is StratAuth, IUniFarm {
	using SafeERC20 for IERC20;

	INFTPool private _farm;
	ICamelotRouter private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;
	uint256 public positionId;
	ISectGrail public sectGrail;

	constructor(
		// here we set sectGrail address instead of pair address
		address sectGrail_,
		address farm_,
		address router_,
		address farmToken_,
		uint256 farmPid_
	) {
		sectGrail = ISectGrail(sectGrail_);
		_farm = INFTPool(farm_);
		_router = ICamelotRouter(router_);
		_farmToken = IERC20(farmToken_);
		_farmId = farmPid_;
		(address pair_, , , , , , , ) = _farm.getPoolInfo();
		_pair = IUniswapV2Pair(pair_);
		_addFarmApprovals();
	}

	///////
	/// Owner Methods
	///////

	function transferSectGrail(address to, uint256 amount) external onlyOwner {
		if (to == address(0)) revert ZeroAddress();
		IERC20(address(sectGrail)).safeTransfer(to, amount);
		emit TransferSectGrail(to, amount);
	}

	function deallocateSectGrail(uint256 amount) external onlyOwner {
		sectGrail.deallocateFromPosition(_farm, positionId, amount);
		emit DeallocateSectGrail(positionId, amount);
	}

	// assumption that _router and _farm are trusted
	function _addFarmApprovals() internal override {
		IERC20(address(_pair)).safeIncreaseAllowance(address(sectGrail), type(uint256).max);
		if (_farmToken.allowance(address(this), address(_router)) == 0)
			_farmToken.safeIncreaseAllowance(address(_router), type(uint256).max);
	}

	function farmRouter() public view override returns (address) {
		return address(_router);
	}

	function pair() public view override returns (IUniswapV2Pair) {
		return _pair;
	}

	function farm() public view returns (address) {
		return address(_farm);
	}

	function _withdrawFromFarm(uint256 amount) internal override {
		positionId = sectGrail.withdrawFromFarm(_farm, positionId, amount);
	}

	function _depositIntoFarm(uint256 amount) internal override {
		positionId = sectGrail.depositIntoFarm(_farm, positionId, amount);
		uint256 nonAllocated = sectGrail.getNonAllocatedBalance(address(this));
		if (nonAllocated > 0) sectGrail.allocateToPosition(_farm, positionId, nonAllocated);
	}

	function _harvestFarm(HarvestSwapParams[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		uint256[] memory farmedTokens = sectGrail.harvestFarm(_farm, positionId);
		if (farmedTokens[0] == 0) return harvested;

		_validatePath(address(_farmToken), swapParams[0].path);
		_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
			farmedTokens[0],
			swapParams[0].min,
			swapParams[0].path,
			address(this),
			address(0),
			block.timestamp
		);

		harvested = new uint256[](1);
		harvested[0] = underlying().balanceOf(address(this));
		emit HarvestedToken(address(_farmToken), harvested[0]);
	}

	function _getFarmLp() internal view override returns (uint256) {
		if (positionId == 0) return 0;
		return sectGrail.getFarmLp(_farm, positionId);
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

	error ZeroAddress();

	event TransferSectGrail(address to, uint256 amount);
	event DeallocateSectGrail(uint256 positionId, uint256 amount);
}
