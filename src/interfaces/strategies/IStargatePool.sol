// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStargatePool is IERC20 {
	function token() external view returns (address);

	function convertRate() external view returns (uint256);

	function amountLPtoLD(uint256) external view returns (uint256);
}
