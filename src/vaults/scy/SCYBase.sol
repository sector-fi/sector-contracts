// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISuperComposableYield } from "../../interfaces/ISuperComposableYield.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { Accounting } from "../../common/Accounting.sol";

// import "hardhat/console.sol";

abstract contract SCYBase is ISuperComposableYield, ReentrancyGuard, Accounting, ERC20 {
	using SafeERC20 for IERC20;

	address internal constant NATIVE = address(0);
	uint256 internal constant ONE = 1e18;

	// solhint-disable no-empty-blocks
	receive() external payable {}

	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

	/*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

	/**
	 * @dev See {ISuperComposableYield-deposit}
	 */
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountTokenToPull,
		uint256 minSharesOut
	) external payable nonReentrant returns (uint256 amountSharesOut) {
		require(isValidBaseToken(tokenIn), "SCY: Invalid tokenIn");

		if (tokenIn == NATIVE) require(amountTokenToPull == 0, "can't pull eth");
		else if (amountTokenToPull != 0) _transferIn(tokenIn, msg.sender, amountTokenToPull);

		uint256 amountIn = _getFloatingAmount(tokenIn);

		amountSharesOut = _deposit(receiver, tokenIn, amountIn);
		require(amountSharesOut >= minSharesOut, "insufficient out");

		_mint(receiver, amountSharesOut);
		emit Deposit(msg.sender, receiver, tokenIn, amountIn, amountSharesOut);
	}

	/**
	 * @dev See {ISuperComposableYield-redeem}
	 */
	function redeem(
		address receiver,
		uint256 amountSharesToRedeem,
		address tokenOut,
		uint256 minTokenOut
	) external nonReentrant returns (uint256 amountTokenOut) {
		require(isValidBaseToken(tokenOut), "SCY: invalid tokenOut");

		// NOTE this is different from reference implementation in that
		// we don't support sending shares to contracts

		// this is to handle a case where the strategy sends funds directly to user
		uint256 amountToTransfer;
		(amountTokenOut, amountToTransfer) = _redeem(receiver, tokenOut, amountSharesToRedeem);
		require(amountTokenOut >= minTokenOut, "insufficient out");

		_burn(msg.sender, amountSharesToRedeem);
		_transferOut(tokenOut, receiver, amountToTransfer);

		emit Redeem(msg.sender, receiver, tokenOut, amountSharesToRedeem, amountTokenOut);
	}

	/**
	 * @notice mint shares based on the deposited base tokens
	 * @param tokenIn base token address used to mint shares
	 * @param amountDeposited amount of base tokens deposited
	 * @return amountSharesOut amount of shares minted
	 */
	function _deposit(
		address receiver,
		address tokenIn,
		uint256 amountDeposited
	) internal virtual returns (uint256 amountSharesOut);

	/**
	 * @notice redeems base tokens based on amount of shares to be burned
	 * @param tokenOut address of the base token to be redeemed
	 * @param amountSharesToRedeem amount of shares to be burned
	 * @return amountTokenOut amount of base tokens redeemed
	 */
	function _redeem(
		address receiver,
		address tokenOut,
		uint256 amountSharesToRedeem
	) internal virtual returns (uint256 amountTokenOut, uint256 tokensToTransfer);

	/*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

	/**
	 * @dev See {ISuperComposableYield-exchangeRateCurrent}
	 */
	function exchangeRateCurrent() external virtual override returns (uint256 res);

	/**
	 * @dev See {ISuperComposableYield-exchangeRateStored}
	 */
	function exchangeRateStored() external view virtual override returns (uint256 res);

	/*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

	// /**
	//  * @dev See {ISuperComposableYield-claimRewards}
	//  */
	// function claimRewards(
	// 	address /*user*/
	// ) external virtual override returns (uint256[] memory rewardAmounts) {
	// 	rewardAmounts = new uint256[](0);
	// }

	// /**
	//  * @dev See {ISuperComposableYield-getRewardTokens}
	//  */
	// function getRewardTokens()
	// 	external
	// 	view
	// 	virtual
	// 	override
	// 	returns (address[] memory rewardTokens)
	// {
	// 	rewardTokens = new address[](0);
	// }

	// /**
	//  * @dev See {ISuperComposableYield-accruredRewards}
	//  */
	// function accruedRewards(
	// 	address /*user*/
	// ) external view virtual override returns (uint256[] memory rewardAmounts) {
	// 	rewardAmounts = new uint256[](0);
	// }

	/*///////////////////////////////////////////////////////////////
                MISC METADATA FUNCTIONS
    //////////////////////////////////////////////////////////////*/

	// /**
	//  * @notice See {ISuperComposableYield-decimals}
	//  */
	// function decimals() public view virtual returns (uint8) {
	// 	return 18;
	// }

	// UTILS

	// function scyToAsset(uint256 exchangeRate, uint256 scyAmount) internal pure returns (uint256) {
	// 	return (scyAmount * exchangeRate) / ONE;
	// }

	// function assetToScy(uint256 exchangeRate, uint256 assetAmount) internal pure returns (uint256) {
	// 	return (assetAmount * ONE) / exchangeRate;
	// }

	// VIRTUALS

	function _getFloatingAmount(address token) internal view virtual returns (uint256);

	/**
	 * @notice See {ISuperComposableYield-getBaseTokens}
	 */
	function getBaseTokens() external view virtual override returns (address[] memory res);

	/**
	 * @dev See {ISuperComposableYield-isValidBaseToken}
	 */
	function isValidBaseToken(address token) public view virtual override returns (bool);

	function _transferIn(
		address token,
		address to,
		uint256 amount
	) internal virtual;

	function _transferOut(
		address token,
		address to,
		uint256 amount
	) internal virtual;

	function _selfBalance(address token) internal view virtual returns (uint256);

	// OVERRIDES
	function totalSupply() public view override(Accounting, ERC20) returns (uint256) {
		return ERC20.totalSupply();
	}
}
