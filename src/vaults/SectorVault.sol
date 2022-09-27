// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626, FixedPointMathLib } from "./ERC4626/ERC4626.sol";

// import "hardhat/console.sol";

contract SectorVault is ERC4626 {
	using FixedPointMathLib for uint256;

	constructor(
		ERC20 _asset,
		string memory _name,
		string memory _symbol,
		address _owner,
		address _guardian,
		address _manager,
		address _treasury,
		uint256 _perforamanceFee
	) ERC4626(_asset, _name, _symbol, _owner, _guardian, _manager, _treasury, _perforamanceFee) {}

	// we may not need locked profit depending on how we handle withdrawals
	// normally it is used to gradually release recent harvest rewards in order to avoid
	// front running harvests (deposit immediately before harvest and withdraw immediately after)
	function lockedProfit() public view virtual returns (uint256) {
		return 0;
	}

	function previewWithdraw(uint256 assets) public view override returns (uint256) {
		uint256 supply = totalSupply() - lockedProfit(); // Saves an extra SLOAD if totalSupply is non-zero.
		return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
	}

	function previewRedeem(uint256 shares) public view override returns (uint256) {
		uint256 supply = totalSupply() - lockedProfit(); // Saves an extra SLOAD if totalSupply is non-zero.
		return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
	}

	function totalAssets() public view override returns (uint256) {
		return asset.balanceOf(address(this));
	}
}
