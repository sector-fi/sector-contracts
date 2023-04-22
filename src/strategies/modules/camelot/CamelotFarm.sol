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
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// import "hardhat/console.sol";

abstract contract CamelotFarm is IUniFarm, IERC721Receiver {
	using SafeERC20 for IERC20;

	INFTPool private _farm;
	ICamelotRouter private _router;
	IERC20 private _farmToken;
	IUniswapV2Pair private _pair;
	uint256 private _farmId;
	uint256 public positionId;
	IXGrailToken public xGrailToken;

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
		_farm.withdrawFromPosition(positionId, amount);
		if (!_farm.exists(positionId)) positionId = 0;
	}

	function _depositIntoFarm(uint256 amount) internal override {
		if (positionId == 0) {
			positionId = _farm.lastTokenId() + 1;
			_farm.createPosition(amount, 0);
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
		// 1. compute how much is needed for max boost
		// 2. use xGrail to boost LP
		// 3. initiate redeem of any extra xGrail
		// 4. finalize redeem of any vested xGrail
		// 5. handle dividends?

		/// simple redeem xGrail immediately
		xGrailToken.redeem(xGrailToken.balanceOf(address(this)), xGrailToken.minRedeemDuration());

		// TODO finailize finished redeems

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
