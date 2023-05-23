// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.16;

/**
 * @title IPoolAddressesProvider
 * @author Aave
 * @notice Defines the basic interface for a Pool Addresses Provider.
 */
interface IPoolAddressesProvider {
	/**
	 * @notice Returns the address of the price oracle.
	 * @return The address of the PriceOracle
	 */
	function getPriceOracle() external view returns (address);

	/**
	 * @notice Returns the address of the price oracle sentinel.
	 * @return The address of the PriceOracleSentinel
	 */
	function getPriceOracleSentinel() external view returns (address);
}
