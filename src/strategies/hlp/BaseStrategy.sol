// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import { Strategy } from "../../interfaces/Strategy.sol";
import { SafeETH } from "../../libraries/SafeETH.sol";

// import "hardhat/console.sol";

abstract contract BaseStrategy is Strategy, Ownable, ReentrancyGuard {
	using SafeERC20 for IERC20;

	modifier onlyVault() {
		require(msg.sender == vault(), "Strat: ONLY_VAULT");
		_;
	}

	modifier onlyGuardian() {
		require(isGuardian(msg.sender), "Strat: ONLY_GUARDIAN");
		_;
	}

	modifier onlyManager() {
		require(isManager(msg.sender), "Strat: ONLY_MANAGER");
		_;
	}

	uint256 constant BPS_ADJUST = 10000;
	uint256 public lastHarvest; // block.timestamp;
	address private _vault;
	uint256 private _shares;

	string public name;
	string public symbol;

	mapping(address => bool) private _managers;
	mapping(address => bool) private _guardians;

	uint256 public BASE_UNIT; // 10 ** decimals

	event Harvest(uint256 harvested); // this is actual the tvl before harvest
	event Deposit(address sender, uint256 amount);
	event Withdraw(address sender, uint256 amount);
	event Rebalance(uint256 shortPrice, uint256 tvlBeforeRebalance, uint256 positionOffset);
	event EmergencyWithdraw(address indexed recipient, IERC20[] tokens);
	event ManagerUpdate(address indexed account, bool isManager);
	event GuardianUpdate(address indexed account, bool isGuardian);
	event VaultUpdate(address indexed vault);
	event UpdatePosition();

	constructor(
		address vault_,
		string memory symbol_,
		string memory name_
	) Ownable() ReentrancyGuard() {
		_vault = vault_;
		symbol = symbol_;
		name = name_;
	}

	// VIEW
	function vault() public view returns (address) {
		return _vault;
	}

	function totalSupply() public view returns (uint256) {
		return _shares;
	}

	/**
	 * @notice
	 *  Returns the share price of the strategy in `underlying` units, multiplied
	 *  by 1e18
	 */
	function getPricePerShare() public view returns (uint256) {
		uint256 bal = balanceOfUnderlying();
		if (_shares == 0) return BASE_UNIT;
		return (bal * BASE_UNIT) / _shares;
	}

	function balanceOfUnderlying(address) public view virtual override returns (uint256) {
		return balanceOfUnderlying();
	}

	function balanceOfUnderlying() public view virtual returns (uint256);

	// PUBLIC METHODS
	function mint(uint256 amount) external onlyVault returns (uint256 errCode) {
		uint256 newShares = _deposit(amount);
		_shares += newShares;
		errCode = 0;
		emit Deposit(msg.sender, amount);
	}

	function redeemUnderlying(uint256 amount)
		external
		override
		onlyVault
		returns (uint256 errCode)
	{
		uint256 burnShares = _withdraw(amount);
		_shares -= burnShares;
		errCode = 0;
		emit Withdraw(msg.sender, amount);
	}

	// GOVERNANCE - MANAGER
	function isManager(address user) public view returns (bool) {
		return _managers[user] || user == owner() || _guardians[user];
	}

	function setManager(address user, bool _isManager) external onlyGuardian {
		_managers[user] = _isManager;
		emit ManagerUpdate(user, _isManager);
	}

	function isGuardian(address user) public view returns (bool) {
		return _guardians[user] || user == owner();
	}

	function setGuardian(address user, bool _isGuardian) external onlyOwner {
		_guardians[user] = _isGuardian;
		emit GuardianUpdate(user, _isGuardian);
	}

	function setVault(address vault_) external onlyOwner {
		_vault = vault_;
		emit VaultUpdate(vault_);
	}

	// emergency only
	// closePosition should be attempted first, if after some tokens are stuck,
	// send them to a designated address
	function emergencyWithdraw(address recipient, IERC20[] calldata tokens)
		external
		override
		onlyVault
	{
		for (uint256 i = 0; i < tokens.length; i++) {
			IERC20 token = tokens[i];
			uint256 balance = token.balanceOf(address(this));
			if (balance != 0) token.safeTransfer(recipient, balance);
		}
		// send ETH to vault (no reason it should go to recipient / owner)
		if (address(this).balance > 0) SafeETH.safeTransferETH(recipient, address(this).balance);
		emit EmergencyWithdraw(recipient, tokens);
	}

	function _deposit(uint256 amount) internal virtual returns (uint256 newShares);

	function _withdraw(uint256 amount) internal virtual returns (uint256 burnShares);

	function isCEther() public pure override returns (bool) {
		return false;
	}

	receive() external payable {}
}
