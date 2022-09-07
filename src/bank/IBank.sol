// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

struct Pool {
	uint96 id;
	bool exists;
	uint8 decimals; // above are packed
	address vault;
	uint256 managementFee; // in basis points
}

interface IBank {
	////////// EVENTS //////////

	/// @param id      vault poolId
	/// @param account address of the owner
	/// @param vault   vault address
	/// @param shares  amount of shares minted
	event Deposit(
		uint96 indexed id,
		address indexed vault,
		address indexed account,
		uint256 shares
	);

	/// @param id      vault poolId
	/// @param vault   vault address
	/// @param account address of the owner
	/// @param shares  amount of shares burned
	event Withdraw(
		uint96 indexed id,
		address indexed vault,
		address indexed account,
		uint256 shares
	);

	/// @param id      vault poolId
	/// @param vault   vault address
	/// @param shares  amount of shares minted
	event TakeFees(uint96 indexed id, address indexed vault, uint256 shares);

	///
	/// @param id      vault poolId
	/// @param vault   vault address
	/// @param tokenId of the pool
	event AddPool(uint96 id, address indexed vault, uint256 indexed tokenId);

	/// @param treasury new treasury address
	event SetTreasury(address treasury);

	function totalShares(address vault, uint96 id) external view returns (uint256);

	function decimals(uint256 tokenId) external view returns (uint8);

	function getPool(uint256 tokenId) external view returns (Pool memory pool);

	function deposit(
		uint96 id,
		address account,
		uint256 poolTokens,
		uint256 totalTokens
	) external returns (uint256);

	function withdraw(
		uint96 id,
		address account,
		uint256 shares,
		uint256 totalTokens
	) external returns (uint256);

	function takeFees(
		uint96 id,
		address recipient,
		uint256 profit,
		uint256 totalTokens
	) external returns (uint256);
}
