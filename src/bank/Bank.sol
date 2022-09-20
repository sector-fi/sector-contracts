// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ERC1155Supply, ERC1155, IERC165 } from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import { Auth, AccessControl } from "../common/Auth.sol";
import { IBank, Pool } from "./IBank.sol";

// import "hardhat/console.sol";

// TODO: should fees be computed in the bank or in vaults?
// we can simplify this contract if so
contract Bank is IBank, ERC1155Supply, Auth {
	/// ERRORS
	error PoolNotFound();
	error PoolExists();

	uint256 constant BASIS_POINTS = 10000;
	uint256 internal constant ONE = 1e18;
	uint256 public constant MIN_LIQUIDITY = 10**3;

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
		if (!pools[tokenId].exists) revert PoolNotFound();
		shares = _assetToShares(tokenId, poolTokens, totalTokens);
		/// Mint the shares to the owner
		_mint(account, tokenId, shares, "");
		emit Deposit(id, msg.sender, account, shares);
	}

	///
	/// @param id          id of vault's pool
	/// @param shares  amount of pool tokens deposited
	/// @param recipient recipient
	///
	function mint(
		uint96 id,
		address recipient,
		uint256 shares
	) public {
		uint256 tokenId = getTokenId(msg.sender, id);
		if (!pools[tokenId].exists) revert PoolNotFound();
		_mint(recipient, tokenId, shares, "");
		emit Deposit(id, msg.sender, recipient, shares);
	}

	/// @dev should only be called by vault
	///
	/// @param id          id of vault's pool
	/// @param poolTokens  amount of pool tokens deposited
	/// @param totalTokens balance of pool tokens in the vault
	///
	/// @return shares amount of shares minted
	function assetToShares(
		uint96 id,
		uint256 poolTokens,
		uint256 totalTokens
	) public view returns (uint256 shares) {
		uint256 tokenId = getTokenId(msg.sender, id);
		shares = _assetToShares(tokenId, poolTokens, totalTokens);
	}

	///
	/// @param tokenId     id token
	/// @param poolTokens  amount of pool tokens deposited
	/// @param totalTokens balance of pool tokens in the vault
	///
	/// @return shares amount of shares minted
	function _assetToShares(
		uint256 tokenId,
		uint256 poolTokens,
		uint256 totalTokens
	) internal view returns (uint256 shares) {
		/// Get the current total amount of shares of the pool
		uint256 _totalSupply = totalSupply(tokenId);

		if (_totalSupply == 0) {
			// MIN_LIQUIDITY amount gets locked on first deposit
			shares = poolTokens - MIN_LIQUIDITY;
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
		if (!pools[tokenId].exists) revert PoolNotFound();

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
	/// @param id      id of vault's asset
	/// @param shares  amount of pool tokens deposited
	/// @param account user account
	///
	function burn(
		uint96 id,
		uint256 shares,
		address account
	) public {
		uint256 tokenId = getTokenId(msg.sender, id);
		if (!pools[tokenId].exists) revert PoolNotFound();
		_burn(account, tokenId, shares);
		emit Withdraw(id, msg.sender, account, shares);
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
		if (!pool.exists) revert PoolNotFound();

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

		_mint(recipient, tokenId, shares, "");

		emit TakeFees(id, msg.sender, shares);

		return shares;
	}

	////////// GOVERNANCE FUNCTIONS //////////

	///
	/// Add a new pool to the bank
	///
	function addPool(Pool calldata newPool) external onlyRole(GUARDIAN) {
		uint256 tokenId = getTokenId(newPool.vault, newPool.id);
		if (pools[tokenId].exists) revert PoolExists();

		/// Add pool to the pools array
		pools[tokenId] = Pool({
			vault: newPool.vault,
			id: newPool.id,
			decimals: newPool.decimals,
			managementFee: newPool.managementFee,
			exists: true
		});

		/// Emit an event
		emit AddPool(newPool.id, newPool.vault, tokenId);
	}

	function setTreasury(address _treasury) external onlyRole(GUARDIAN) {
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

	// OVERRIDES
	function supportsInterface(bytes4 interfaceId)
		public
		pure
		override(AccessControl, ERC1155)
		returns (bool)
	{
		return interfaceId == type(IERC165).interfaceId;
	}

	function _beforeTokenTransfer(
		address operator,
		address from,
		address to,
		uint256[] memory ids,
		uint256[] memory amounts,
		bytes memory data
	) internal override {
		super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

		// when minting tokens for the first time
		// we lock the MIN_LIQUIDITY amount to
		// prevent rounding error manipulation
		for (uint256 i; i < ids.length; i++) {
			uint256 id = ids[i];
			if (from == address(0) && to != address(1) && totalSupply(id) == 0) {
				_mint(address(1), id, MIN_LIQUIDITY, "");
			}
		}
	}
}
