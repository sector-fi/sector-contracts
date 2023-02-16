// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import { ERC20Upgradeable as ERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FixedPointMathLib } from "../../libraries/FixedPointMathLib.sol";
import { IERC4626 } from "../../interfaces/ERC4626/IERC4626.sol";
import { Accounting } from "../../common/Accounting.sol";
import { AuthU, AuthConfig } from "../../common/AuthU.sol";
import { FeesU, FeeConfig } from "../../common/FeesU.sol";
import { IWETH } from "../../interfaces/uniswap/IWETH.sol";
import { SectorErrors } from "../../interfaces/SectorErrors.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

// import "hardhat/console.sol";

/// @notice Minimal ERC4626 tokenized Vault implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/mixins/ERC4626.sol)
abstract contract ERC4626U is
	Initializable,
	ERC20,
	AuthU,
	Accounting,
	FeesU,
	IERC4626,
	ReentrancyGuardUpgradeable,
	ERC20PermitUpgradeable,
	PausableUpgradeable,
	SectorErrors
{
	using SafeERC20 for IERC20;
	using FixedPointMathLib for uint256;

	// gap that allows us to add new inhereted contracts without breaking the storage layout
	uint256[100] private __gapPre;

	/*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

	// locked liquidity to prevent rounding errors
	uint256 public constant MIN_LIQUIDITY = 1e3;
	uint256 public version;

	/*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

	IERC20 public asset;
	// flag that allows the vault to consume native asset
	bool public useNativeAsset;
	uint256 public maxTvl;

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function __ERC4626_init(
		IERC20 _asset,
		string memory _name,
		string memory _symbol,
		bool _useNativeAsset
	) public onlyInitializing {
		__ERC20_init(_name, _symbol);
		__ERC20Permit_init(_name);
		useNativeAsset = _useNativeAsset;
		asset = _asset;
	}

	receive() external payable {}

	function decimals() public view virtual override returns (uint8) {
		return ERC20(address(asset)).decimals();
	}

	function totalAssets() public view virtual override returns (uint256);

	/*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

	function deposit(uint256 assets, address receiver)
		public
		payable
		virtual
		nonReentrant
		returns (uint256 shares)
	{
		if (totalAssets() + assets > maxTvl) revert MaxTvlReached();

		// This check is no longer necessary because we use MIN_LIQUIDITY
		// Check for rounding error since we round down in previewDeposit.
		// require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
		shares = previewDeposit(assets);

		// Need to transfer before minting or ERC777s could reenter.
		if (useNativeAsset && msg.value == assets) IWETH(address(asset)).deposit{ value: assets }();
		else asset.safeTransferFrom(msg.sender, address(this), assets);

		// lock minimum liquidity if totalSupply is 0
		if (totalSupply() == 0) {
			if (MIN_LIQUIDITY > shares) revert MinLiquidity();
			shares -= MIN_LIQUIDITY;
			_mint(address(1), MIN_LIQUIDITY);
		}

		_mint(receiver, shares);

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function mint(uint256 shares, address receiver)
		public
		payable
		virtual
		nonReentrant
		returns (uint256 assets)
	{
		assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.
		if (totalAssets() + assets > maxTvl) revert MaxTvlReached();

		// Need to transfer before minting or ERC777s could reenter.
		if (useNativeAsset && msg.value == assets) IWETH(address(asset)).deposit{ value: assets }();
		else asset.safeTransferFrom(msg.sender, address(this), assets);

		// lock minimum liquidity if totalSupply is 0
		if (totalSupply() == 0) {
			if (MIN_LIQUIDITY > shares) revert MinLiquidity();
			shares -= MIN_LIQUIDITY;
			_mint(address(1), MIN_LIQUIDITY);
		}

		_mint(receiver, shares);

		emit Deposit(msg.sender, receiver, assets, shares);

		afterDeposit(assets, shares);
	}

	function withdraw(
		uint256 assets,
		address receiver,
		address owner
	) public virtual returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

		// if not owner, allowance must be enforced
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Withdraw(msg.sender, receiver, owner, assets, shares);

		asset.safeTransfer(receiver, assets);
	}

	function redeem(
		uint256 shares,
		address receiver,
		address owner
	) public virtual returns (uint256 assets) {
		// if not owner, allowance must be enforced
		if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);

		// This check is no longer necessary because we use MIN_LIQUIDITY
		// Check for rounding error since we round down in previewRedeem.
		// require((assets = previewRedeem(shares)) != 0, "ZEROassetS");
		assets = previewRedeem(shares);

		beforeWithdraw(assets, shares);

		_burn(owner, shares);

		emit Withdraw(msg.sender, receiver, owner, assets, shares);

		asset.safeTransfer(receiver, assets);
	}

	function previewDeposit(uint256 assets) public view virtual returns (uint256) {
		return convertToShares(assets);
	}

	function previewMint(uint256 shares) public view virtual returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

		return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
	}

	function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
		uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
		return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
	}

	function previewRedeem(uint256 shares) public view virtual returns (uint256) {
		return convertToAssets(shares);
	}

	/*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

	function setMaxTvl(uint256 _maxTvl) public onlyRole(MANAGER) {
		maxTvl = _maxTvl;
		emit MaxTvlUpdated(_maxTvl);
	}

	function maxDeposit(address) public view override returns (uint256) {
		uint256 _totalAssets = totalAssets();
		return _totalAssets > maxTvl ? 0 : maxTvl - _totalAssets;
	}

	function maxMint(address) public view override returns (uint256) {
		return convertToShares(maxDeposit(address(0)));
	}

	function maxWithdraw(address owner) public view virtual returns (uint256) {
		return convertToAssets(balanceOf(owner));
	}

	function maxRedeem(address owner) public view virtual returns (uint256) {
		return balanceOf(owner);
	}

	/*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

	function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {}

	function afterDeposit(uint256 assets, uint256 shares) internal virtual {}

	event MaxTvlUpdated(uint256 maxTvl);

	/// ERC20 overrides

	function totalSupply() public view virtual override(Accounting, ERC20) returns (uint256) {
		return ERC20.totalSupply();
	}

	/// PAUSABLE

	function pause() public onlyRole(GUARDIAN) {
		_pause();
	}

	function unpause() public onlyRole(GUARDIAN) {
		_unpause();
	}

	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal override whenNotPaused {
		super._beforeTokenTransfer(from, to, amount);
	}

	uint256[50] private __gap;
}
