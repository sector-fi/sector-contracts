// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { PriceUtils, UniUtils, IUniswapV2Pair } from "../../utils/PriceUtils.sol";
import { SCYVault } from "vaults/ERC5115/SCYVault.sol";
import { IERC20Metadata as IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IStrategy } from "interfaces/IStrategy.sol";
import { SCYStratUtils } from "./SCYStratUtils.sol";

import "hardhat/console.sol";

abstract contract UniswapMixin is PriceUtils, SCYStratUtils {
	using UniUtils for IUniswapV2Pair;

	IUniswapV2Pair uniPair;
	address short;

	function configureUniswapMixin(address _uniPair, address _short) public {
		uniPair = IUniswapV2Pair(_uniPair);
		short = _short;
	}

	function moveUniPrice(uint256 fraction) public virtual {
		if (address(uniPair) == address(0)) return;
		moveUniswapPrice(address(uniPair), address(underlying), short, fraction);
	}
}
