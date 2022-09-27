// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IERC4626 {
	event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

	event Withdraw(
		address indexed caller,
		address indexed receiver,
		address indexed owner,
		uint256 assets,
		uint256 shares
	);

	/*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

	function asset() external view returns (ERC20);

	/*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	function deposit(uint256 assets, address receiver) external returns (uint256 shares);

	function mint(uint256 shares, address receiver) external returns (uint256 assets);

	function withdraw(
		uint256 assets,
		address receiver,
		address owner
	) external returns (uint256 shares);

	function redeem(
		uint256 shares,
		address receiver,
		address owner
	) external returns (uint256 assets);

	/*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	function maxDeposit(address) external view returns (uint256);

	function maxMint(address) external view returns (uint256);

	function maxWithdraw(address owner) external view returns (uint256);

	function maxRedeem(address owner) external view returns (uint256);
}
