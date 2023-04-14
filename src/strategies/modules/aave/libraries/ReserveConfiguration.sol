// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { DataTypes } from "./DataTypes.sol";

/**
 * @title ReserveConfiguration library
 * @author Aave
 * @notice Implements the bitmap logic to handle the reserve configuration
 */
library ReserveConfiguration {
	uint256 internal constant LTV_MASK =                       0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000; // prettier-ignore
	uint256 internal constant LIQUIDATION_THRESHOLD_MASK =     0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFF; // prettier-ignore
	uint256 internal constant LIQUIDATION_BONUS_MASK =         0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFF; // prettier-ignore
	uint256 internal constant DECIMALS_MASK =                  0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant ACTIVE_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant FROZEN_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant BORROWING_MASK =                 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant STABLE_BORROWING_MASK =          0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant PAUSED_MASK =                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant BORROWABLE_IN_ISOLATION_MASK =   0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFDFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant SILOED_BORROWING_MASK =          0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFBFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant FLASHLOAN_ENABLED_MASK =         0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF7FFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant RESERVE_FACTOR_MASK =            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant BORROW_CAP_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant SUPPLY_CAP_MASK =                0xFFFFFFFFFFFFFFFFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant LIQUIDATION_PROTOCOL_FEE_MASK =  0xFFFFFFFFFFFFFFFFFFFFFF0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant EMODE_CATEGORY_MASK =            0xFFFFFFFFFFFFFFFFFFFF00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant UNBACKED_MINT_CAP_MASK =         0xFFFFFFFFFFF000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore
	uint256 internal constant DEBT_CEILING_MASK =              0xF0000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // prettier-ignore

	/// @dev For the LTV, the start bit is 0 (up to 15), hence no bitshifting is needed
	uint256 internal constant LIQUIDATION_THRESHOLD_START_BIT_POSITION = 16;
	uint256 internal constant LIQUIDATION_BONUS_START_BIT_POSITION = 32;
	uint256 internal constant RESERVE_DECIMALS_START_BIT_POSITION = 48;
	uint256 internal constant IS_ACTIVE_START_BIT_POSITION = 56;
	uint256 internal constant IS_FROZEN_START_BIT_POSITION = 57;
	uint256 internal constant BORROWING_ENABLED_START_BIT_POSITION = 58;
	uint256 internal constant STABLE_BORROWING_ENABLED_START_BIT_POSITION = 59;
	uint256 internal constant IS_PAUSED_START_BIT_POSITION = 60;
	uint256 internal constant BORROWABLE_IN_ISOLATION_START_BIT_POSITION = 61;
	uint256 internal constant SILOED_BORROWING_START_BIT_POSITION = 62;
	uint256 internal constant FLASHLOAN_ENABLED_START_BIT_POSITION = 63;
	uint256 internal constant RESERVE_FACTOR_START_BIT_POSITION = 64;
	uint256 internal constant BORROW_CAP_START_BIT_POSITION = 80;
	uint256 internal constant SUPPLY_CAP_START_BIT_POSITION = 116;
	uint256 internal constant LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION = 152;
	uint256 internal constant EMODE_CATEGORY_START_BIT_POSITION = 168;
	uint256 internal constant UNBACKED_MINT_CAP_START_BIT_POSITION = 176;
	uint256 internal constant DEBT_CEILING_START_BIT_POSITION = 212;

	uint256 internal constant MAX_VALID_LTV = 65535;
	uint256 internal constant MAX_VALID_LIQUIDATION_THRESHOLD = 65535;
	uint256 internal constant MAX_VALID_LIQUIDATION_BONUS = 65535;
	uint256 internal constant MAX_VALID_DECIMALS = 255;
	uint256 internal constant MAX_VALID_RESERVE_FACTOR = 65535;
	uint256 internal constant MAX_VALID_BORROW_CAP = 68719476735;
	uint256 internal constant MAX_VALID_SUPPLY_CAP = 68719476735;
	uint256 internal constant MAX_VALID_LIQUIDATION_PROTOCOL_FEE = 65535;
	uint256 internal constant MAX_VALID_EMODE_CATEGORY = 255;
	uint256 internal constant MAX_VALID_UNBACKED_MINT_CAP = 68719476735;
	uint256 internal constant MAX_VALID_DEBT_CEILING = 1099511627775;

	uint256 public constant DEBT_CEILING_DECIMALS = 2;
	uint16 public constant MAX_RESERVES_COUNT = 128;

	/**
	 * @notice Gets the Loan to Value of the reserve
	 * @param self The reserve configuration
	 * @return The loan to value
	 */
	function getLtv(DataTypes.ReserveConfigurationMap memory self) internal pure returns (uint256) {
		return self.data & ~LTV_MASK;
	}

	/**
	 * @notice Gets the liquidation threshold of the reserve
	 * @param self The reserve configuration
	 * @return The liquidation threshold
	 */
	function getLiquidationThreshold(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return
			(self.data & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the liquidation bonus of the reserve
	 * @param self The reserve configuration
	 * @return The liquidation bonus
	 */
	function getLiquidationBonus(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the decimals of the underlying asset of the reserve
	 * @param self The reserve configuration
	 * @return The decimals of the asset
	 */
	function getDecimals(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the active state of the reserve
	 * @param self The reserve configuration
	 * @return The active state
	 */
	function getActive(DataTypes.ReserveConfigurationMap memory self) internal pure returns (bool) {
		return (self.data & ~ACTIVE_MASK) != 0;
	}

	/**
	 * @notice Gets the frozen state of the reserve
	 * @param self The reserve configuration
	 * @return The frozen state
	 */
	function getFrozen(DataTypes.ReserveConfigurationMap memory self) internal pure returns (bool) {
		return (self.data & ~FROZEN_MASK) != 0;
	}

	/**
	 * @notice Gets the paused state of the reserve
	 * @param self The reserve configuration
	 * @return The paused state
	 */
	function getPaused(DataTypes.ReserveConfigurationMap memory self) internal pure returns (bool) {
		return (self.data & ~PAUSED_MASK) != 0;
	}

	/**
	 * @notice Gets the borrowable in isolation flag for the reserve.
	 * @dev If the returned flag is true, the asset is borrowable against isolated collateral. Assets borrowed with
	 * isolated collateral is accounted for in the isolated collateral's total debt exposure.
	 * @dev Only assets of the same family (eg USD stablecoins) should be borrowable in isolation mode to keep
	 * consistency in the debt ceiling calculations.
	 * @param self The reserve configuration
	 * @return The borrowable in isolation flag
	 */
	function getBorrowableInIsolation(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (bool)
	{
		return (self.data & ~BORROWABLE_IN_ISOLATION_MASK) != 0;
	}

	/**
	 * @notice Gets the siloed borrowing flag for the reserve.
	 * @dev When this flag is set to true, users borrowing this asset will not be allowed to borrow any other asset.
	 * @param self The reserve configuration
	 * @return The siloed borrowing flag
	 */
	function getSiloedBorrowing(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (bool)
	{
		return (self.data & ~SILOED_BORROWING_MASK) != 0;
	}

	/**
	 * @notice Gets the borrowing state of the reserve
	 * @param self The reserve configuration
	 * @return The borrowing state
	 */
	function getBorrowingEnabled(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (bool)
	{
		return (self.data & ~BORROWING_MASK) != 0;
	}

	/**
	 * @notice Gets the stable rate borrowing state of the reserve
	 * @param self The reserve configuration
	 * @return The stable rate borrowing state
	 */
	function getStableRateBorrowingEnabled(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (bool)
	{
		return (self.data & ~STABLE_BORROWING_MASK) != 0;
	}

	/**
	 * @notice Gets the reserve factor of the reserve
	 * @param self The reserve configuration
	 * @return The reserve factor
	 */
	function getReserveFactor(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the borrow cap of the reserve
	 * @param self The reserve configuration
	 * @return The borrow cap
	 */
	function getBorrowCap(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~BORROW_CAP_MASK) >> BORROW_CAP_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the supply cap of the reserve
	 * @param self The reserve configuration
	 * @return The supply cap
	 */
	function getSupplyCap(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the debt ceiling for the asset if the asset is in isolation mode
	 * @param self The reserve configuration
	 * @return The debt ceiling (0 = isolation mode disabled)
	 */
	function getDebtCeiling(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~DEBT_CEILING_MASK) >> DEBT_CEILING_START_BIT_POSITION;
	}

	/**
	 * @dev Gets the liquidation protocol fee
	 * @param self The reserve configuration
	 * @return The liquidation protocol fee
	 */
	function getLiquidationProtocolFee(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return
			(self.data & ~LIQUIDATION_PROTOCOL_FEE_MASK) >>
			LIQUIDATION_PROTOCOL_FEE_START_BIT_POSITION;
	}

	/**
	 * @dev Gets the unbacked mint cap of the reserve
	 * @param self The reserve configuration
	 * @return The unbacked mint cap
	 */
	function getUnbackedMintCap(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~UNBACKED_MINT_CAP_MASK) >> UNBACKED_MINT_CAP_START_BIT_POSITION;
	}

	/**
	 * @dev Gets the eMode asset category
	 * @param self The reserve configuration
	 * @return The eMode category for the asset
	 */
	function getEModeCategory(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256)
	{
		return (self.data & ~EMODE_CATEGORY_MASK) >> EMODE_CATEGORY_START_BIT_POSITION;
	}

	/**
	 * @notice Gets the flashloanable flag for the reserve
	 * @param self The reserve configuration
	 * @return The flashloanable flag
	 */
	function getFlashLoanEnabled(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (bool)
	{
		return (self.data & ~FLASHLOAN_ENABLED_MASK) != 0;
	}

	/**
	 * @notice Gets the configuration flags of the reserve
	 * @param self The reserve configuration
	 * @return The state flag representing active
	 * @return The state flag representing frozen
	 * @return The state flag representing borrowing enabled
	 * @return The state flag representing stableRateBorrowing enabled
	 * @return The state flag representing paused
	 */
	function getFlags(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (
			bool,
			bool,
			bool,
			bool,
			bool
		)
	{
		uint256 dataLocal = self.data;

		return (
			(dataLocal & ~ACTIVE_MASK) != 0,
			(dataLocal & ~FROZEN_MASK) != 0,
			(dataLocal & ~BORROWING_MASK) != 0,
			(dataLocal & ~STABLE_BORROWING_MASK) != 0,
			(dataLocal & ~PAUSED_MASK) != 0
		);
	}

	/**
	 * @notice Gets the configuration parameters of the reserve from storage
	 * @param self The reserve configuration
	 * @return The state param representing ltv
	 * @return The state param representing liquidation threshold
	 * @return The state param representing liquidation bonus
	 * @return The state param representing reserve decimals
	 * @return The state param representing reserve factor
	 * @return The state param representing eMode category
	 */
	function getParams(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (
			uint256,
			uint256,
			uint256,
			uint256,
			uint256,
			uint256
		)
	{
		uint256 dataLocal = self.data;

		return (
			dataLocal & ~LTV_MASK,
			(dataLocal & ~LIQUIDATION_THRESHOLD_MASK) >> LIQUIDATION_THRESHOLD_START_BIT_POSITION,
			(dataLocal & ~LIQUIDATION_BONUS_MASK) >> LIQUIDATION_BONUS_START_BIT_POSITION,
			(dataLocal & ~DECIMALS_MASK) >> RESERVE_DECIMALS_START_BIT_POSITION,
			(dataLocal & ~RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_START_BIT_POSITION,
			(dataLocal & ~EMODE_CATEGORY_MASK) >> EMODE_CATEGORY_START_BIT_POSITION
		);
	}

	/**
	 * @notice Gets the caps parameters of the reserve from storage
	 * @param self The reserve configuration
	 * @return The state param representing borrow cap
	 * @return The state param representing supply cap.
	 */
	function getCaps(DataTypes.ReserveConfigurationMap memory self)
		internal
		pure
		returns (uint256, uint256)
	{
		uint256 dataLocal = self.data;

		return (
			(dataLocal & ~BORROW_CAP_MASK) >> BORROW_CAP_START_BIT_POSITION,
			(dataLocal & ~SUPPLY_CAP_MASK) >> SUPPLY_CAP_START_BIT_POSITION
		);
	}
}
