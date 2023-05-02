// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IXGrailToken } from "./interfaces/IXGrailToken.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { INFTPool } from "./interfaces/INFTPool.sol";
import { INFTHandler } from "./interfaces/INFTHandler.sol";
import { ISectGrail } from "./interfaces/IsectGrail.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";

// import "hardhat/console.sol";

/// @title sectGrail
/// @notice sectGrail is a liquid wrapper for xGrail, an escrowed Grail token
/// @dev contract Camelot contract links:
/// xGrail: https://arbiscan.io/address/0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b//
/// USDC-ETH NFTPool: https://arbiscan.io/address/0x6bc938aba940fb828d39daa23a94dfc522120c11
/// YieldBooster: https://arbiscan.io/address/0xD27c373950E7466C53e5Cd6eE3F70b240dC0B1B1#code
contract sectGrail is
	ISectGrail,
	ERC20Upgradeable,
	INFTHandler,
	ERC20PermitUpgradeable,
	ReentrancyGuardUpgradeable
{
	using SafeERC20 for IERC20;

	uint256[200] __pre_gap; // gap for upgrade safety allows to add inhertiance items

	mapping(address => uint256) public allocations;
	mapping(uint256 => address) public positionOwners;

	modifier onlyPositionOwner(uint256 positionId) {
		if (positionOwners[positionId] != msg.sender) revert NotPositionOwner();
		_;
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	IXGrailToken public xGrailToken;
	IERC20 public grailToken;

	// TODO is it better to hardcode xGrail address?
	function initialize(address _xGrail) public initializer {
		__ERC20_init("sectGRAIL", "sectGRAIL");
		xGrailToken = IXGrailToken(_xGrail);
		grailToken = IERC20(xGrailToken.grailToken());
	}

	/// @notice convert xGrail in the contract to sectGrail
	/// @dev we include allocated xGrail and check against totalSupply of sectGrail
	/// any extra amount can be minted to the user
	function _mintFromBalance(address to) internal returns (uint256) {
		(uint256 allocated, ) = xGrailToken.getXGrailBalance(address(this));

		// dont include redeems - redeems should be burned
		uint256 amount = xGrailToken.balanceOf(address(this)) + allocated - totalSupply();
		_mint(to, amount);
		return amount;
	}

	/// @notice deposit lp tokens into a Camelot farm
	function depositIntoFarm(
		INFTPool _farm,
		uint256 amount,
		uint256 positionId,
		address lp
	) external nonReentrant returns (uint256) {
		IERC20(lp).safeTransferFrom(msg.sender, address(this), amount);

		if (IERC20(lp).allowance(address(this), address(_farm)) < amount)
			IERC20(lp).safeApprove(address(_farm), type(uint256).max);

		// positionId = 0 means that position does not exist yet
		if (positionId == 0) {
			positionId = _farm.lastTokenId() + 1;
			_farm.createPosition(amount, 0);
			positionOwners[positionId] = msg.sender;
		} else {
			if (positionOwners[positionId] != msg.sender) revert NotPositionOwner();
			_farm.addToPosition(positionId, amount);
		}

		emit DepositIntoFarm(msg.sender, address(_farm), positionId, amount);
		return positionId;
	}

	/// @notice withdraw lp tokens from a Camelot farm
	function withdrawFromFarm(
		INFTPool _farm,
		uint256 amount,
		uint256 positionId,
		address lp
	) external nonReentrant onlyPositionOwner(positionId) returns (uint256) {
		address usageAddress = _farm.yieldBooster();
		uint256 xGrailAllocation = xGrailToken.usageAllocations(address(this), usageAddress);
		_farm.withdrawFromPosition(positionId, amount);

		// when full balance is removed from position, the position gets deleted
		// xGrail get deallocated from a deleted position
		// if the position has been delted, reset the positionId to 0
		if (!_farm.exists(positionId)) {
			// when position gets removed we need to reset the allocation amount
			uint256 allocationChange = xGrailAllocation -
				xGrailToken.usageAllocations(address(this), usageAddress);

			allocations[msg.sender] -= allocationChange;
			// subtract deallocation fee amount
			uint256 deallocationFeeAmount = (allocationChange *
				xGrailToken.usagesDeallocationFee(usageAddress)) / 10000;
			// burn the deallocation fee worth of sectGrail from user
			_burn(msg.sender, deallocationFeeAmount);
			positionId = 0;
		}

		IERC20(lp).safeTransfer(msg.sender, amount);
		uint256 grailBalance = grailToken.balanceOf(address(this));
		if (grailBalance > 0) grailToken.safeTransfer(msg.sender, grailBalance);
		_mintFromBalance(msg.sender);

		emit WithdrawFromFarm(msg.sender, address(_farm), positionId, amount);
		return positionId;
	}

	/// @notice harvest camelot farm and allocate xGrail to the position
	function harvestFarm(
		INFTPool _farm,
		uint256 positionId,
		address[] memory tokens
	) external nonReentrant onlyPositionOwner(positionId) returns (uint256[] memory harvested) {
		_farm.harvestPosition(positionId);
		harvested = new uint256[](tokens.length);
		for (uint256 i = 0; i < tokens.length; i++) {
			IERC20 token = IERC20(tokens[i]);
			harvested[i] = token.balanceOf(address(this));
			if (harvested[i] > 0) token.safeTransfer(msg.sender, harvested[i]);
		}

		/// allocate all xGrail to the farm
		bytes memory usageData = abi.encode(_farm, positionId);
		_mintFromBalance(msg.sender);
		allocate(_farm.yieldBooster(), type(uint256).max, usageData);
		emit HarvestFarm(msg.sender, address(_farm), positionId, harvested);
	}

	/// @notice get lp tokens staked in a Camelot farm
	function getFarmLp(INFTPool _farm, uint256 positionId) public view returns (uint256) {
		if (positionId == 0) return 0;
		(uint256 lp, , , , , , , ) = _farm.getStakingPosition(positionId);
		return lp;
	}

	/// @notice allocate xGrail to a usage contract
	function allocate(
		address usageAddress,
		uint256 amount,
		bytes memory usageData
	) public {
		uint256 allocated = allocations[msg.sender];
		uint256 available = balanceOf(msg.sender) - allocated;
		amount = amount > available ? available : amount;
		if (amount == 0) revert InsufficientBalance();

		if (xGrailToken.getUsageApproval(address(this), usageAddress) < amount)
			xGrailToken.approveUsage(usageAddress, type(uint256).max);

		xGrailToken.allocate(usageAddress, amount, usageData);
		allocations[msg.sender] = allocated + amount;
		emit Allocate(msg.sender, usageAddress, amount, usageData);
	}

	/// @notice deallocate xGrail from a usage contract
	function deallocate(
		address usageAddress,
		uint256 amount,
		bytes memory usageData
	) public {
		xGrailToken.deallocate(usageAddress, amount, usageData);
		allocations[msg.sender] = allocations[msg.sender] - amount;

		/// burn deallocation fee sectGrail
		uint256 deallocationFeeAmount = (amount * xGrailToken.usagesDeallocationFee(usageAddress)) /
			10000;
		_burn(msg.sender, deallocationFeeAmount);
		emit Deallocate(msg.sender, usageAddress, amount, usageData);
	}

	/// @dev ensure that only non-allocated sectGrail can be transferred
	function _beforeTokenTransfer(
		address from,
		address to,
		uint256 amount
	) internal override {
		super._beforeTokenTransfer(from, to, amount);
		if (from == address(0)) return;
		uint256 currentAllocation = allocations[msg.sender];
		uint256 unAllocated = balanceOf(msg.sender) - currentAllocation;
		if (amount > unAllocated) revert CannotTransferAllocatedTokens();
	}

	/// VEIW FUNCTIONS

	/// @notice get the total amount of xGrail allocated by a user
	function getAllocations(address user) external view returns (uint256) {
		return allocations[user];
	}

	/// @notice get the total amount of xGrail that can be allocated by a user
	function getNonAllocatedBalance(address user) external view returns (uint256) {
		return balanceOf(user) - allocations[user];
	}

	/// NFT HANDLER OVERRIDES

	function onNFTHarvest(
		address send,
		address to,
		uint256 tokenId,
		uint256 grailAmount,
		uint256 xGrailAmount
	) external returns (bool) {
		return true;
	}

	function onNFTAddToPosition(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	function onNFTWithdraw(
		address operator,
		uint256 tokenId,
		uint256 lpAmount
	) external returns (bool) {
		return true;
	}

	/**
	 * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
	 * by `operator` from `from`, this function is called.
	 *
	 * It must return its Solidity selector to confirm the token transfer.
	 * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
	 *
	 * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
	 */
	function onERC721Received(
		address operator,
		address from,
		uint256 tokenId,
		bytes calldata data
	) external returns (bytes4) {
		return this.onERC721Received.selector;
	}

	error CannotTransferAllocatedTokens();
	error InsufficientBalance();
	error NotPositionOwner();
}
