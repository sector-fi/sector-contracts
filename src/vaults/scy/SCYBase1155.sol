// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { ISuperComposableYield } from "../../interfaces/ISuperComposableYield.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "hardhat/console.sol";

abstract contract SCYBase1155 is Initializable, ISuperComposableYield, ReentrancyGuardUpgradeable {
	using SafeERC20 for IERC20;
	address internal constant NATIVE = address(0);
	uint256 internal constant ONE = 1e18;

	address public yieldToken;

	function __SCYBase_init_(address _yieldToken) public onlyInitializing {
		yieldToken = _yieldToken;
	}

	// solhint-disable no-empty-blocks
	receive() external payable {}

	/*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

	/**
	 * @dev See {ISuperComposableYield-deposit}
	 */
	function deposit(
		address receiver,
		address tokenIn,
		uint256 amountIn,
		uint256 minSharesOut
	) external payable nonReentrant returns (uint256 amountSharesOut) {
		require(isValidBaseToken(tokenIn), "SCY: Invalid tokenIn");

		if (tokenIn == NATIVE) require(amountIn == 0, "can't pull eth");
		else if (amountIn != 0) _transferIn(tokenIn, msg.sender, amountIn);
		// SCY standard allows for tokens to be sent to this contract prior to calling deposit
		// this improves composability, but add complexity and potential gas fees

		amountSharesOut = _deposit(receiver, tokenIn, amountIn);
		require(amountSharesOut >= minSharesOut, "insufficient out");

		// _mint(receiver, amountSharesOut);

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

		amountTokenOut = _redeem(receiver, tokenOut, amountSharesToRedeem);
		require(amountTokenOut >= minTokenOut, "insufficient out");

		_transferOut(tokenOut, receiver, amountTokenOut);

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
	) internal virtual returns (uint256 amountTokenOut);

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

	/**
	 * @dev See {ISuperComposableYield-claimRewards}
	 */
	function claimRewards(
		address /*user*/
	) external virtual override returns (uint256[] memory rewardAmounts) {
		rewardAmounts = new uint256[](0);
	}

	/**
	 * @dev See {ISuperComposableYield-getRewardTokens}
	 */
	function getRewardTokens()
		external
		view
		virtual
		override
		returns (address[] memory rewardTokens)
	{
		rewardTokens = new address[](0);
	}

	/**
	 * @dev See {ISuperComposableYield-accruredRewards}
	 */
	function accruedRewards(
		address /*user*/
	) external view virtual override returns (uint256[] memory rewardAmounts) {
		rewardAmounts = new uint256[](0);
	}

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

	function strategy() public virtual returns (address);

	uint256[50] private __gap;
}
