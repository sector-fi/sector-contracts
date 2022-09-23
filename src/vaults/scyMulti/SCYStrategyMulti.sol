// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SCYBaseMulti, Initializable, IERC20, IERC20Metadata, SafeERC20 } from "./SCYBaseMulti.sol";
import { IMX } from "../../strategies/imx/IMX.sol";
import { AuthU } from "../../common/AuthU.sol";
import { FeesU } from "../../common/FeesU.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";
import { TreasuryU } from "../../common/TreasuryU.sol";
import { Bank } from "../../bank/Bank.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "hardhat/console.sol";

struct StrategyMulti {
	bytes32 symbol;
	address addr;
	bool exists;
	uint256 strategyId; // this is strategy specific token if 1155
	address yieldToken;
	IERC20 underlying;
	uint128 maxTvl; // pack all params and balances
	uint128 balance; // strategy balance in underlying
	uint128 uBalance; // underlying balance
	uint128 yBalance; // yield token balance
}

abstract contract SCYStrategyMulti {
	function _stratDeposit(StrategyMulti storage strategy, uint256 amount)
		internal
		virtual
		returns (uint256);

	function _stratRedeem(
		StrategyMulti storage strategy,
		address to,
		uint256 amount
	) internal virtual returns (uint256 amntOut, uint256 amntToTransfer);

	function _stratClosePosition(StrategyMulti storage strategy) internal virtual returns (uint256);

	function _stratGetAndUpdateTvl(StrategyMulti storage strategy)
		internal
		virtual
		returns (uint256);

	function _strategyTvl(StrategyMulti storage strategy) internal view virtual returns (uint256);

	function _stratMaxTvl(StrategyMulti storage strategy) internal view virtual returns (uint256);

	function _stratCollateralToUnderlying(StrategyMulti storage strategy)
		internal
		view
		virtual
		returns (uint256);
}
