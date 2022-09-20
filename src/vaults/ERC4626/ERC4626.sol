// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { IERC4626 } from "../../interfaces/IERC4626.sol";
import { Bank, Pool } from "../../bank/Bank.sol";
import { Auth } from "../../common/Auth.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626 is IERC4626, Auth {
	using SafeERC20 for ERC20;
	using FixedPointMathLib for uint256;
	using SafeCast for uint256;

	/*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

	ERC20 public immutable asset;
	Bank public immutable bank;

	// TODO do we want to store this in the contract?
	// string memory _name,
	// string memory _symbol
	constructor(
		ERC20 _asset,
		Bank _bank,
		uint256 _managementFee,
		address _owner,
		address _guardian,
		address _manager
	) Auth(_owner, _guardian, _manager) {
		asset = _asset;
		bank = _bank;
		bank.addPool(
			Pool({
				vault: address(this),
				id: 0,
				managementFee: _managementFee.toUint16(),
				decimals: asset.decimals(),
				exists: true
			})
		);
	}

	/*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
		// Need to transfer before minting or ERC777s could reenter.
		asset.safeTransferFrom(msg.sender, address(this), assets);

		// TODO make sure totalAssets is adjusted for lockedProfit
		uint256 total = totalAssets();
		shares = bank.deposit(0, receiver, assets, total);

		// don't need to do this if we have MIN_LIQUiDITY
		// if (shares == 0) revert ZeroShares();

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
		assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

		// Need to transfer before minting or ERC777s could reenter.
		asset.safeTransferFrom(msg.sender, address(this), assets);

		bank.mint(0, receiver, shares);

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function withdraw(
		uint256 assets,
		address receiver,
		address owner
	) public virtual returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

		if (msg.sender != owner) {
			// TODO granular approvals?
			if (!bank.isApprovedForAll(owner, msg.sender)) revert MissingApproval();
		}

		beforeWithdraw(assets, shares);

		bank.burn(0, shares, owner);

		emit Withdraw(msg.sender, receiver, owner, assets, shares);

		asset.safeTransfer(receiver, assets);
	}

	function redeem(
		uint256 shares,
		address receiver,
		address owner
	) public virtual returns (uint256 assets) {
		if (msg.sender != owner) {
			// TODO granula approvals?
			if (!bank.isApprovedForAll(owner, msg.sender)) revert MissingApproval();
		}
		// Check for rounding error since we round down in previewRedeem.
		// don't need to do this if we have MIN_LIQUiDITY
		// require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
		beforeWithdraw(assets, shares);

		// remove locked profit on redeem
		uint256 total = totalAssets() - lockedProfit();
		shares = bank.withdraw(0, owner, shares, total);
		emit Withdraw(msg.sender, receiver, owner, assets, shares);
		asset.safeTransfer(receiver, assets);
	}

	/*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

	function totalAssets() public view virtual returns (uint256);

	function lockedProfit() public view virtual returns (uint256) {
		return 0;
	}

	function convertToShares(uint256 assets) public view virtual returns (uint256) {
		return bank.assetToShares(0, assets, totalAssets());
	}

	function convertToAssets(uint256 shares) public view virtual returns (uint256) {
		uint256 supply = bank.totalShares(address(this), 0);
		return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
	}

	function previewDeposit(uint256 assets) public view virtual returns (uint256) {
		return bank.assetToShares(0, assets, totalAssets());
	}

	function previewMint(uint256 shares) public view virtual returns (uint256) {
		uint256 supply = bank.totalShares(address(this), 0);
		return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
	}

	function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
		uint256 supply = bank.totalShares(address(this), 0);
		// remove locked profit on redeem
		uint256 total = totalAssets() - lockedProfit();
		return supply == 0 ? assets : assets.mulDivUp(supply, total);
	}

	function previewRedeem(uint256 shares) public view virtual returns (uint256) {
		return bank.assetToShares(0, shares, totalAssets());
	}

	/*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	function maxDeposit(address) public view virtual returns (uint256) {
		return type(uint256).max;
	}

	function maxMint(address) public view virtual returns (uint256) {
		return type(uint256).max;
	}

	function maxWithdraw(address owner) public view virtual returns (uint256) {
		// TODO add a lib to avoid external calls
		uint256 tokenId = bank.getTokenId(address(this), 0);
		return convertToAssets(bank.balanceOf(owner, tokenId));
	}

	function maxRedeem(address owner) public view virtual returns (uint256) {
		// TODO add a lib to avoid external calls
		uint256 tokenId = bank.getTokenId(address(this), 0);
		return bank.balanceOf(owner, tokenId);
	}

	/*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

	function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

	function afterDeposit(uint256 assets, uint256 shares) internal virtual {}

	error MissingApproval();
}
