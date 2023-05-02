// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { INFTPool } from "./interfaces/INFTPool.sol";
import { IXGrailToken } from "./interfaces/IXGrailToken.sol";
import { IYieldBooster } from "./interfaces/IYieldBooster.sol";
import { ICamelotMaster } from "./interfaces/ICamelotMaster.sol";
import { ICamelotRouter } from "./interfaces/ICamelotRouter.sol";
import { INFTHandler } from "./interfaces/INFTHandler.sol";

import { IUniswapV2Pair } from "../../../interfaces/uniswap/IUniswapV2Pair.sol";

import { IUniFarm, HarvestSwapParams } from "../../mixins/IUniFarm.sol";
import { IWETH } from "../../../interfaces/uniswap/IWETH.sol";

// import "hardhat/console.sol";

/// @title Camelot Farm Module
/// @notice This is a simple farm module that self-manages xGrail rewards
/// the disadvantage is that this makes it harder to move/re-allocate xGrail
/// to a different contract if the strategy is depricated or redeployed
/// this farm module is depreated in favor of CamelotSectGrailFarm
abstract contract CamelotFarm is IUniFarm, INFTHandler {
	using SafeERC20 for IERC20;

	INFTPool private _farm;
	ICamelotRouter private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;
	uint256 public positionId;
	IXGrailToken public xGrailToken;
	address public yieldBooster;

	constructor(
		address pair_,
		address farm_,
		address router_,
		address farmToken_,
		uint256 farmPid_
	) {
		_farm = INFTPool(farm_);
		_router = ICamelotRouter(router_);
		_farmToken = IERC20(farmToken_);
		_pair = IUniswapV2Pair(pair_);
		_farmId = farmPid_;
		(, , address _xGrailToken, , , , , ) = _farm.getPoolInfo();
		xGrailToken = IXGrailToken(_xGrailToken);
		yieldBooster = _farm.yieldBooster();
		_addFarmApprovals();
	}

	// assumption that _router and _farm are trusted
	function _addFarmApprovals() internal override {
		IERC20(address(_pair)).safeApprove(address(_farm), type(uint256).max);
		if (_farmToken.allowance(address(this), address(_router)) == 0)
			_farmToken.safeApprove(address(_router), type(uint256).max);
		xGrailToken.approveUsage(yieldBooster, type(uint256).max);
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
		_farm.withdrawFromPosition(positionId, amount);
		// note: when full balance is removed from position, the position gets deleted
		// xGrail get deallocated from a deleted position
		// if the position has been delted, reset the positionId to 0
		if (!_farm.exists(positionId)) positionId = 0;
	}

	function _depositIntoFarm(uint256 amount) internal override {
		if (positionId == 0) {
			positionId = _farm.lastTokenId() + 1;
			_farm.createPosition(amount, 0);
			uint256 xGrail = xGrailToken.balanceOf(address(this));
			/// when creating a new position, allocate the full xGrail ballance to the farm
			if (xGrail > 0) {
				bytes memory usageData = abi.encode(_farm, positionId);
				xGrailToken.allocate(yieldBooster, xGrail, usageData);
			}
		} else {
			_farm.addToPosition(positionId, amount);
		}
	}

	function _harvestFarm(HarvestSwapParams[] calldata swapParams)
		internal
		override
		returns (uint256[] memory harvested)
	{
		_farm.harvestPosition(positionId);
		uint256 farmHarvest = _farmToken.balanceOf(address(this));
		if (farmHarvest == 0) return harvested;

		// TODO
		// owner methods to redeem or re-allocate xGrail?
		// can also use the emergencyAction method to execute...

		/// allocate all xGrail to the farm
		bytes memory usageData = abi.encode(_farm, positionId);
		xGrailToken.allocate(yieldBooster, xGrailToken.balanceOf(address(this)), usageData);

		_validatePath(address(_farmToken), swapParams[0].path);
		_router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
			farmHarvest,
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
		(uint256 lp, , , , , , , ) = _farm.getStakingPosition(positionId);
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

	function onNFTHarvest(
		address send,
		address to,
		uint256 tokenId,
		uint256 grailAmount,
		uint256 xGrailAmount
	) external returns (bool) {
		return true;
	}

	function onNFTAddToPosition(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	function onNFTWithdraw(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	/**
	 * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
	 * by `operator` from `from`, this function is called.
	 *
	 * It must return its Solidity selector to confirm the token transfer.
	 * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
	 *
	 * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
	 */
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) external returns (bytes4) {
		return this.onERC721Received.selector;
	}
}
