// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { DataTypes } from "../libraries/DataTypes.sol";

/**
 * @title IPool
 * @author Aave
 * @notice Defines the basic interface for an Aave Pool.
 */
interface IPool {
	/// @dev address provider
	function ADDRESSES_PROVIDER() external view returns (address);

	/**
	 * @notice Mints an `amount` of aTokens to the `onBehalfOf`
	 * @param asset The address of the underlying asset to mint
	 * @param amount The amount to mint
	 * @param onBehalfOf The address that will receive the aTokens
	 * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
	 *   0 if the action is executed directly by the user, without any middle-man
	 */
	function mintUnbacked(
		address asset,
		uint256 amount,
		address onBehalfOf,
		uint16 referralCode
	) external;

	/**
	 * @notice Back the current unbacked underlying with `amount` and pay `fee`.
	 * @param asset The address of the underlying asset to back
	 * @param amount The amount to back
	 * @param fee The amount paid in fees
	 * @return The backed amount
	 */
	function backUnbacked(
		address asset,
		uint256 amount,
		uint256 fee
	) external returns (uint256);

	/**
	 * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
	 * - E.g. User supplies 100 USDC and gets in return 100 aUSDC
	 * @param asset The address of the underlying asset to supply
	 * @param amount The amount to be supplied
	 * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
	 *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
	 *   is a different wallet
	 * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
	 *   0 if the action is executed directly by the user, without any middle-man
	 */
	function supply(
		address asset,
		uint256 amount,
		address onBehalfOf,
		uint16 referralCode
	) external;

	/**
	 * @notice Supply with transfer approval of asset to be supplied done via permit function
	 * see: https://eips.ethereum.org/EIPS/eip-2612 and https://eips.ethereum.org/EIPS/eip-713
	 * @param asset The address of the underlying asset to supply
	 * @param amount The amount to be supplied
	 * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
	 *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
	 *   is a different wallet
	 * @param deadline The deadline timestamp that the permit is valid
	 * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
	 *   0 if the action is executed directly by the user, without any middle-man
	 * @param permitV The V parameter of ERC712 permit sig
	 * @param permitR The R parameter of ERC712 permit sig
	 * @param permitS The S parameter of ERC712 permit sig
	 */
	function supplyWithPermit(
		address asset,
		uint256 amount,
		address onBehalfOf,
		uint16 referralCode,
		uint256 deadline,
		uint8 permitV,
		bytes32 permitR,
		bytes32 permitS
	) external;

	/**
	 * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
	 * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
	 * @param asset The address of the underlying asset to withdraw
	 * @param amount The underlying amount to be withdrawn
	 *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
	 * @param to The address that will receive the underlying, same as msg.sender if the user
	 *   wants to receive it on his own wallet, or a different address if the beneficiary is a
	 *   different wallet
	 * @return The final amount withdrawn
	 */
	function withdraw(
		address asset,
		uint256 amount,
		address to
	) external returns (uint256);

	/**
	 * @notice Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
	 * already supplied enough collateral, or he was given enough allowance by a credit delegator on the
	 * corresponding debt token (StableDebtToken or VariableDebtToken)
	 * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
	 *   and 100 stable/variable debt tokens, depending on the `interestRateMode`
	 * @param asset The address of the underlying asset to borrow
	 * @param amount The amount to be borrowed
	 * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
	 * @param referralCode The code used to register the integrator originating the operation, for potential rewards.
	 *   0 if the action is executed directly by the user, without any middle-man
	 * @param onBehalfOf The address of the user who will receive the debt. Should be the address of the borrower itself
	 * calling the function if he wants to borrow against his own collateral, or the address of the credit delegator
	 * if he has been given credit delegation allowance
	 */
	function borrow(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		uint16 referralCode,
		address onBehalfOf
	) external;

	/**
	 * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
	 * - E.g. User repays 100 USDC, burning 100 variable/stable debt tokens of the `onBehalfOf` address
	 * @param asset The address of the borrowed underlying asset previously borrowed
	 * @param amount The amount to repay
	 * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
	 * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
	 * @param onBehalfOf The address of the user who will get his debt reduced/removed. Should be the address of the
	 * user calling the function if he wants to reduce/remove his own debt, or the address of any other
	 * other borrower whose debt should be removed
	 * @return The final amount repaid
	 */
	function repay(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		address onBehalfOf
	) external returns (uint256);

	/**
	 * @notice Repay with transfer approval of asset to be repaid done via permit function
	 * see: https://eips.ethereum.org/EIPS/eip-2612 and https://eips.ethereum.org/EIPS/eip-713
	 * @param asset The address of the borrowed underlying asset previously borrowed
	 * @param amount The amount to repay
	 * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
	 * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
	 * @param onBehalfOf Address of the user who will get his debt reduced/removed. Should be the address of the
	 * user calling the function if he wants to reduce/remove his own debt, or the address of any other
	 * other borrower whose debt should be removed
	 * @param deadline The deadline timestamp that the permit is valid
	 * @param permitV The V parameter of ERC712 permit sig
	 * @param permitR The R parameter of ERC712 permit sig
	 * @param permitS The S parameter of ERC712 permit sig
	 * @return The final amount repaid
	 */
	function repayWithPermit(
		address asset,
		uint256 amount,
		uint256 interestRateMode,
		address onBehalfOf,
		uint256 deadline,
		uint8 permitV,
		bytes32 permitR,
		bytes32 permitS
	) external returns (uint256);

	/**
	 * @notice Repays a borrowed `amount` on a specific reserve using the reserve aTokens, burning the
	 * equivalent debt tokens
	 * - E.g. User repays 100 USDC using 100 aUSDC, burning 100 variable/stable debt tokens
	 * @dev  Passing uint256.max as amount will clean up any residual aToken dust balance, if the user aToken
	 * balance is not enough to cover the whole debt
	 * @param asset The address of the borrowed underlying asset previously borrowed
	 * @param amount The amount to repay
	 * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
	 * @param interestRateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
	 * @return The final amount repaid
	 */
	function repayWithATokens(
		address asset,
		uint256 amount,
		uint256 interestRateMode
	) external returns (uint256);

	/**
	 * @notice Allows a borrower to swap his debt between stable and variable mode, or vice versa
	 * @param asset The address of the underlying asset borrowed
	 * @param interestRateMode The current interest rate mode of the position being swapped: 1 for Stable, 2 for Variable
	 */
	function swapBorrowRateMode(address asset, uint256 interestRateMode) external;

	/**
	 * @notice Rebalances the stable interest rate of a user to the current stable rate defined on the reserve.
	 * - Users can be rebalanced if the following conditions are satisfied:
	 *     1. Usage ratio is above 95%
	 *     2. the current supply APY is below REBALANCE_UP_THRESHOLD * maxVariableBorrowRate, which means that too
	 *        much has been borrowed at a stable rate and suppliers are not earning enough
	 * @param asset The address of the underlying asset borrowed
	 * @param user The address of the user to be rebalanced
	 */
	function rebalanceStableBorrowRate(address asset, address user) external;

	/**
	 * @notice Allows suppliers to enable/disable a specific supplied asset as collateral
	 * @param asset The address of the underlying asset supplied
	 * @param useAsCollateral True if the user wants to use the supply as collateral, false otherwise
	 */
	function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

	/**
	 * @notice Returns the user account data across all the reserves
	 * @param user The address of the user
	 * @return totalCollateralBase The total collateral of the user in the base currency used by the price feed
	 * @return totalDebtBase The total debt of the user in the base currency used by the price feed
	 * @return availableBorrowsBase The borrowing power left of the user in the base currency used by the price feed
	 * @return currentLiquidationThreshold The liquidation threshold of the user
	 * @return ltv The loan to value of The user
	 * @return healthFactor The current health factor of the user
	 */
	function getUserAccountData(address user)
		external
		view
		returns (
			uint256 totalCollateralBase,
			uint256 totalDebtBase,
			uint256 availableBorrowsBase,
			uint256 currentLiquidationThreshold,
			uint256 ltv,
			uint256 healthFactor
		);

	/**
	 * @notice Returns the configuration of the reserve
	 * @param asset The address of the underlying asset of the reserve
	 * @return The configuration of the reserve
	 */
	function getConfiguration(address asset)
		external
		view
		returns (DataTypes.ReserveConfigurationMap memory);

	/**
	 * @notice Returns the state and configuration of the reserve
	 * @param asset The address of the underlying asset of the reserve
	 * @return The state and configuration data of the reserve
	 */
	function getReserveData(address asset) external view returns (DataTypes.ReserveData memory);
}
