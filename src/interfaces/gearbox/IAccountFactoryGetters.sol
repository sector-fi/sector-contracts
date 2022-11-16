// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2022
pragma solidity ^0.8.10;

interface IAccountFactoryGetters {
	/// @dev Returns address of next available creditAccount
	function getNext(address creditAccount) external view returns (address);

	/// @dev Returns head of list of unused credit accounts
	function head() external view returns (address);

	/// @dev Returns tail of list of unused credit accounts
	function tail() external view returns (address);

	/// @dev Returns quantity of unused credit accounts in the stock
	function countCreditAccountsInStock() external view returns (uint256);

	/// @dev Returns credit account address by its id
	function creditAccounts(uint256 id) external view returns (address);

	/// @dev Quantity of credit accounts
	function countCreditAccounts() external view returns (uint256);
}
