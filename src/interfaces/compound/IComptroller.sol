// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./ICTokenInterfaces.sol";

interface IComptroller {
	/*** Assets You Are In ***/

	function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);

	function exitMarket(address cToken) external returns (uint256);

	/*** Policy Hooks ***/

	function mintAllowed(
		address cToken,
		address minter,
		uint256 mintAmount
	) external returns (uint256);

	function mintVerify(
		address cToken,
		address minter,
		uint256 mintAmount,
		uint256 mintTokens
	) external;

	function redeemAllowed(
		address cToken,
		address redeemer,
		uint256 redeemTokens
	) external returns (uint256);

	function redeemVerify(
		address cToken,
		address redeemer,
		uint256 redeemAmount,
		uint256 redeemTokens
	) external;

	function borrowAllowed(
		address cToken,
		address borrower,
		uint256 borrowAmount
	) external returns (uint256);

	function borrowVerify(
		address cToken,
		address borrower,
		uint256 borrowAmount
	) external;

	function repayBorrowAllowed(
		address cToken,
		address payer,
		address borrower,
		uint256 repayAmount
	) external returns (uint256);

	function repayBorrowVerify(
		address cToken,
		address payer,
		address borrower,
		uint256 repayAmount,
		uint256 borrowerIndex
	) external;

	function liquidateBorrowAllowed(
		address cTokenBorrowed,
		address cTokenCollateral,
		address liquidator,
		address borrower,
		uint256 repayAmount
	) external returns (uint256);

	function liquidateBorrowVerify(
		address cTokenBorrowed,
		address cTokenCollateral,
		address liquidator,
		address borrower,
		uint256 repayAmount,
		uint256 seizeTokens
	) external;

	function seizeAllowed(
		address cTokenCollateral,
		address cTokenBorrowed,
		address liquidator,
		address borrower,
		uint256 seizeTokens
	) external returns (uint256);

	function seizeVerify(
		address cTokenCollateral,
		address cTokenBorrowed,
		address liquidator,
		address borrower,
		uint256 seizeTokens
	) external;

	function transferAllowed(
		address cToken,
		address src,
		address dst,
		uint256 transferTokens
	) external returns (uint256);

	function transferVerify(
		address cToken,
		address src,
		address dst,
		uint256 transferTokens
	) external;

	function claimComp(address holder) external;

	function claimComp(address holder, ICTokenErc20[] memory cTokens) external;

	/*** Liquidity/Liquidation Calculations ***/

	function liquidateCalculateSeizeTokens(
		address cTokenBorrowed,
		address cTokenCollateral,
		uint256 repayAmount
	) external view returns (uint256, uint256);
}

interface UnitrollerAdminStorage {
	/**
	 * @notice Administrator for this contract
	 */
	// address external admin;
	function admin() external view returns (address);

	/**
	 * @notice Pending administrator for this contract
	 */
	// address external pendingAdmin;
	function pendingAdmin() external view returns (address);

	/**
	 * @notice Active brains of Unitroller
	 */
	// address external comptrollerImplementation;
	function comptrollerImplementation() external view returns (address);

	/**
	 * @notice Pending brains of Unitroller
	 */
	// address external pendingComptrollerImplementation;
	function pendingComptrollerImplementation() external view returns (address);
}

interface ComptrollerV1Storage is UnitrollerAdminStorage {
	/**
	 * @notice Oracle which gives the price of any given asset
	 */
	// PriceOracle external oracle;
	function oracle() external view returns (address);

	/**
	 * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
	 */
	// uint external closeFactorMantissa;
	function closeFactorMantissa() external view returns (uint256);

	/**
	 * @notice Multiplier representing the discount on collateral that a liquidator receives
	 */
	// uint external liquidationIncentiveMantissa;
	function liquidationIncentiveMantissa() external view returns (uint256);

	/**
	 * @notice Max number of assets a single account can participate in (borrow or use as collateral)
	 */
	// uint external maxAssets;
	function maxAssets() external view returns (uint256);

	/**
	 * @notice Per-account mapping of "assets you are in", capped by maxAssets
	 */
	// mapping(address => CToken[]) external accountAssets;
	// function accountAssets(address) external view returns (CToken[]);
}

abstract contract ComptrollerV2Storage is ComptrollerV1Storage {
	enum Version {
		VANILLA,
		COLLATERALCAP,
		WRAPPEDNATIVE
	}

	struct Market {
		bool isListed;
		uint256 collateralFactorMantissa;
		mapping(address => bool) accountMembership;
		bool isComped;
		// Version version;
	}

	/**
	 * @notice Official mapping of cTokens -> Market metadata
	 * @dev Used e.g. to determine if a market is supported
	 */
	mapping(address => Market) public markets;

	/**
	 * @notice The Pause Guardian can pause certain actions as a safety mechanism.
	 *  Actions which allow users to remove their own assets cannot be paused.
	 *  Liquidation / seizing / transfer can only be paused globally, not by market.
	 */
	// address external pauseGuardian;
	// bool external _mintGuardianPaused;
	// bool external _borrowGuardianPaused;
	// bool external transferGuardianPaused;
	// bool external seizeGuardianPaused;
	// mapping(address => bool) external mintGuardianPaused;
	// mapping(address => bool) external borrowGuardianPaused;
}

abstract contract ComptrollerV3Storage is ComptrollerV2Storage {
	// struct CompMarketState {
	//     /// @notice The market's last updated compBorrowIndex or compSupplyIndex
	//     uint224 index;
	//     /// @notice The block number the index was last updated at
	//     uint32 block;
	// }
	// /// @notice A list of all markets
	// CToken[] external allMarkets;
	// /// @notice The rate at which the flywheel distributes COMP, per block
	// uint external compRate;
	// /// @notice The portion of compRate that each market currently receives
	// mapping(address => uint) external compSpeeds;
	// /// @notice The COMP market supply state for each market
	// mapping(address => CompMarketState) external compSupplyState;
	// /// @notice The COMP market borrow state for each market
	// mapping(address => CompMarketState) external compBorrowState;
	// /// @notice The COMP borrow index for each market for each supplier as of the last time they accrued COMP
	// mapping(address => mapping(address => uint)) external compSupplierIndex;
	// /// @notice The COMP borrow index for each market for each borrower as of the last time they accrued COMP
	// mapping(address => mapping(address => uint)) external compBorrowerIndex;
	// /// @notice The COMP accrued but not yet transferred to each user
	// mapping(address => uint) external compAccrued;
}

abstract contract ComptrollerV4Storage is ComptrollerV3Storage {
	// @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
	// address external borrowCapGuardian;
	function borrowCapGuardian() external view virtual returns (address);

	// @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
	// mapping(address => uint) external borrowCaps;
	function borrowCaps(address) external view virtual returns (uint256);
}

abstract contract ComptrollerV5Storage is ComptrollerV4Storage {
	// @notice The supplyCapGuardian can set supplyCaps to any number for any market. Lowering the supply cap could disable supplying to the given market.
	// address external supplyCapGuardian;
	function supplyCapGuardian() external view virtual returns (address);

	// @notice Supply caps enforced by mintAllowed for each cToken address. Defaults to zero which corresponds to unlimited supplying.
	// mapping(address => uint) external supplyCaps;
	function supplyCaps(address) external view virtual returns (uint256);
}
