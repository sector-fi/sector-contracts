// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ERC1155Supply, ERC1155, IERC165 } from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import { Auth, AccessControl } from "../common/Auth.sol";
import { IBank, Pool } from "./IBank.sol";

// TODO: should fees be computed in the bank or in vaults?
// we can simplify this contract if so
contract Bank is IBank, ERC1155Supply, Auth {
	uint256 constant BASIS_POINTS = 10000;
	uint256 internal constant ONE = 1e18;

	/// List of pools
	mapping(uint256 => Pool) public pools;

	address public treasury;

	constructor(
		string memory uri, // ex: https://game.example/api/item/{id}.json
		address owner,
		address guardian,
		address manager,
		address _treasury
	) ERC1155(uri) Auth(owner, guardian, manager) {
		treasury = _treasury;
		emit SetTreasury(_treasury);
	}

	///
	/// @param id          id of vault's pool
	/// @param account     owner of the shares
	/// @param poolTokens  amount of pool tokens deposited
	/// @param totalTokens balance of pool tokens in the vault
	///
	/// @return shares amount of shares minted
	function deposit(
		uint96 id,
		address account,
		uint256 poolTokens,
		uint256 totalTokens
	) external override returns (uint256 shares) {
		uint256 tokenId = getTokenId(msg.sender, id);

		/// Get the pool by its index
		Pool memory pool = pools[tokenId]; // storage or memory for gas optimization?
		require(pool.exists, "POOL_NOT_FOUND");

		/// Get the current total amount of shares of the pool
		uint256 _totalSupply = totalSupply(tokenId);
		if (_totalSupply == 0) {
			// todo add multiple for precision?
			shares = poolTokens;
		} else {
			/// When converting between pool tokens and shares, we always maintain this formula:
			/// (shares / totalShares) = (poolTokens / totalTokens)
			///
			/// When depositing pool tokens and minting shares, this formula can be rearranged to:
			/// shares = (totalShares * poolTokens) / totalTokens
			///
			/// Since the pool tokens have already been deposited before we mint the shares,
			/// we subtract these tokens from the total. This gives us the total before depositing:
			/// shares = (totalShares * poolTokens) / (totalTokens - poolTokens)
			shares = (_totalSupply * poolTokens) / (totalTokens - poolTokens);
		}

		/// Mint the shares to the owner
		_mint(account, tokenId, shares, "");

		emit Deposit(id, msg.sender, account, shares);

		return shares;
	}

	///
	/// @param id          id of vault's pool
	/// @param account     owner of the shares
	/// @param shares      amount of shares to burn
	/// @param totalTokens balance of pool tokens in the vault
	///
	/// @return poolTokens amount of pool tokens to withdraw
	function withdraw(
		uint96 id,
		address account,
		uint256 shares,
		uint256 totalTokens
	) external override returns (uint256 poolTokens) {
		uint256 tokenId = getTokenId(msg.sender, id);

		Pool storage pool = pools[tokenId];
		require(pool.exists, "POOL_NOT_FOUND");

		uint256 _totalSupply = totalSupply(tokenId);

		/// Burn the shares from the owner
		_burn(account, tokenId, shares);

		/// Calculate the amount of pool tokens to withdraw --
		///
		/// When converting between pool tokens and shares, we always maintain this formula:
		/// (shares / totalShares) = (poolTokens / totalTokens)
		///
		/// When withdrawing pool tokens and burning shares, this formula can be rearranged to:
		/// poolTokens = (totalTokens * shares) / totalShares
		///
		/// Since the shares have already been burned before
		/// we withdraw use totalSupply before burn
		poolTokens = (totalTokens * shares) / _totalSupply;

		emit Withdraw(id, msg.sender, account, shares);

		return poolTokens;
	}

	///
	/// @param id          vault pool id
	/// @param poolTokens  amount of pool tokens compounded
	/// @param totalTokens balance of pool tokens in the vault
	/// @param recipient  of fees
	///
	/// @return shares amount of shares minted
	function takeFees(
		uint96 id,
		address recipient,
		uint256 poolTokens,
		uint256 totalTokens
	) external override returns (uint256 shares) {
		uint256 tokenId = getTokenId(msg.sender, id);

		Pool storage pool = pools[tokenId];
		require(pool.exists, "POOL_NOT_FOUND");

		/// Check if there is a management fee
		if (pool.managementFee == 0) return shares;

		// we fallback to treasury address if recipient is not privided
		recipient = recipient == address(0) ? treasury : recipient;

		/// Compounding deposits pool tokens and mints shares to the treasury according to the compound fee
		///
		/// When depositing, we use this formula to convert pool tokens to shares:
		/// shares = (totalShares * poolTokens) / (totalTokens - poolTokens)
		///
		/// When compounding, we multiply the shares from this formula by the compound fee as a percentage:
		/// shares = ((totalShares * poolTokens) / (totalTokens - poolTokens)) * (compoundFee / ONE_HUNDRED_PERCENT)
		///
		/// To increase precision, we rearrange this to perform all multiplication before division:
		/// shares = ((totalShares * poolTokens) * compoundFee) / ((totalTokens - poolTokens) * ONE_HUNDRED_PERCENT)
		shares =
			((totalSupply(tokenId) * poolTokens) * pool.managementFee) /
			((totalTokens - poolTokens) * BASIS_POINTS);

		/// Mint the shares to the treasury
		_mint(recipient, tokenId, shares, "");

		/// Emit an event
		emit TakeFees(id, msg.sender, shares);

		/// TODO: docs
		return shares;
	}

	////////// GOVERNANCE FUNCTIONS //////////

	///
	/// Add a new pool to the bank
	/// Only owner can call this function
	///
	function addPool(Pool calldata newPool) external onlyOwner {
		uint256 tokenId = getTokenId(newPool.vault, newPool.id);
		require(false == pools[tokenId].exists, "POOL_FOUND");

		/// Validate the fees before adding the pool
		// _validateFees(newPool.depositFee, newPool.withdrawFee, newPool.compoundFee);

		/// Add pool to the pools array
		pools[tokenId] = newPool;

		/// Emit an event
		emit AddPool(newPool.id, newPool.vault, tokenId);
	}

	function setTreasury(address _treasury) external onlyRole(GOVERNANCE) {
		treasury = _treasury;
		emit SetTreasury(_treasury);
	}

	function totalShares(address vault, uint96 poolId)
		external
		view
		override(IBank)
		returns (uint256)
	{
		uint256 tokenId = getTokenId(vault, poolId);
		return totalSupply(tokenId);
	}

	/// TODO: make sure this is superior to a lookup table
	/// token ids are a combination of vault address + poolId
	function getTokenId(address vault, uint96 poolId) public pure returns (uint256) {
		return uint256(bytes32(bytes20(vault)) | bytes32(uint256(poolId)));
	}

	function getTokenInfo(uint256 tokenId) public pure returns (address vault, uint256 poolId) {
		poolId = uint96(tokenId);
		vault = address(bytes20(bytes32(tokenId) ^ bytes32(uint256(poolId))));
	}

	// TODO: what are the ideal method params
	function getPool(uint256 tokenId) external view override returns (Pool memory pool) {
		return pools[tokenId];
	}

	// TODO do we need this and what are the ideal method params
	function decimals(uint256 tokenId) external view override returns (uint8) {
		return pools[tokenId].decimals;
	}

	// overrides
	function supportsInterface(bytes4 interfaceId)
		public
		pure
		override(AccessControl, ERC1155)
		returns (bool)
	{
		return interfaceId == type(IERC165).interfaceId;
	}
}
