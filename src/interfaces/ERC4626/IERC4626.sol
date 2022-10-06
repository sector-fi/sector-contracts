// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.16;

interface IERC4626 {
	event Deposit(
		address indexed sender,
		address indexed owner,
		uint256 assets,
		uint256 shares
	);

	event Withdraw(
		address indexed sender,
		address indexed receiver,
		address indexed owner,
		uint256 assets,
		uint256 shares
	);

	/*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

	function asset() external view returns (address assetTokenAddress);

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

	function maxDeposit(address receiver) external view returns (uint256 maxAssets);

	function maxMint(address receiver) external view returns (uint256 maxShares);

	function maxWithdraw(address owner) external view returns (uint256 maxAssets);

	function maxRedeem(address owner) external view returns (uint256 maxShares);
}
