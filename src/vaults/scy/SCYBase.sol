// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISuperComposableYield } from "../../interfaces/scy/ISuperComposableYield.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MetadataUpgradeable as IERC20Metadata } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import { Accounting } from "../../common/Accounting.sol";

import "hardhat/console.sol";

abstract contract SCYBase is ISuperComposableYield, ReentrancyGuard, Accounting, ERC20 {
	using SafeERC20 for IERC20;

	address internal constant NATIVE = address(0);
	uint256 internal constant ONE = 1e18;
	uint256 public constant MIN_LIQUIDITY = 1e3;
	// override if false
	bool public sendERC20ToStrategy = true;

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

		if (tokenIn == NATIVE) {
			require(amountTokenToPull == 0, "can't pull eth");
			_depositNative();
		} else if (amountTokenToPull != 0) _transferIn(tokenIn, msg.sender, amountTokenToPull);

		// this depends on strategy
		// this supports depositing directly into strategy to save gas
		uint256 amountIn = _getFloatingAmount(tokenIn);
		if (amountIn == 0) revert ZeroAmount();

		amountSharesOut = _deposit(receiver, tokenIn, amountIn);
		if (amountSharesOut < minSharesOut) revert InsufficientOut(amountSharesOut, minSharesOut);

		// lock minimum liquidity if totalSupply is 0
		if (totalSupply() == 0) {
			if (MIN_LIQUIDITY > amountSharesOut) revert MinLiquidity();
			amountSharesOut -= MIN_LIQUIDITY;
			_mint(address(1), MIN_LIQUIDITY);
		}

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
		if (amountToTransfer > 0) _transferOut(tokenOut, receiver, amountToTransfer);

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

	function _depositNative() internal virtual;

	// OVERRIDES
	function totalSupply() public view override(Accounting, ERC20) returns (uint256) {
		return ERC20.totalSupply();
	}

	error MinLiquidity();
	error ZeroAmount();
	error InsufficientOut(uint256 amountOut, uint256 minOut);
}
