// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity 0.8.16;

// import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import { FixedPointMathLib } from "../libraries/FixedPointMathLib.sol";

// import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// import "../interfaces/uniswap/IWETH.sol";

// // import "hardhat/console.sol";

// import { IERC4626 } from "../interfaces/IERC4626.sol";
// import { ERC4626 } from "./ERC4626/ERC4626.sol";

// /// @title Rari Vault (rvToken)
// /// @author Transmissions11 and JetJadeja
// /// @notice Flexible, minimalist, and gas-optimized yield aggregator for
// /// earning interest on any ERC20 token.
// contract VaultUpgradable is ERC4626, ReentrancyGuard {
// 	using SafeCast for uint256;
// 	using SafeERC20 for IERC20;
// 	using FixedPointMathLib for uint256;

// 	uint256 public constant MINIMUM_LIQUIDITY = 10**3;

// 	constructor() {}

// 	/// @notice The base unit of the underlying token and hence rvToken.
// 	/// @dev Equal to 10 ** decimals. Used for fixed point arithmetic.
// 	uint256 public BASE_UNIT;

// 	uint256 private _decimals;

// 	/// @notice Emitted when the Vault is initialized.
// 	/// @param user The authorized user who triggered the initialization.
// 	event Initialized(address indexed user);

// 	/// @notice Creates a new Vault that accepts a specific underlying token.
// 	function initialize(
// 		address _owner,
// 		address _manager,
// 		uint256 _feePercent,
// 		uint64 _harvestDelay,
// 		uint128 _harvestWindow
// 	) external {
// 		__ERC20_init(
// 			// ex: Scion USDC.e Vault
// 			string(abi.encodePacked("Scion ", ERC20(address(_UNDERLYING)).name(), " Vault")),
// 			// ex: sUSDC.e
// 			string(abi.encodePacked("sc", ERC20(address(_UNDERLYING)).symbol()))
// 		);

// 		__ReentrancyGuard_init();
// 		__Ownable_init();

// 		_decimals = ERC20(address(_UNDERLYING)).decimals();

// 		UNDERLYING = _UNDERLYING;

// 		BASE_UNIT = 10**_decimals;

// 		// configure
// 		setManager(_manager, true);
// 		setFeePercent(_feePercent);

// 		// delay must be set first
// 		setHarvestDelay(_harvestDelay);
// 		setHarvestWindow(_harvestWindow);

// 		emit Initialized(msg.sender);

// 		// must be call after all other inits
// 		_transferOwnership(_owner);

// 		// defaults to open vaults
// 		_maxTvl = type(uint256).max;
// 		_stratMaxTvl = type(uint256).max;

// 		version = 2;
// 	}

// 	function decimals() public view override returns (uint8) {
// 		return uint8(_decimals);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                                  CONSTANTS
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice The maximum number of elements allowed on the withdrawal stack.
// 	/// @dev Needed to prevent denial of service attacks by queue operators.
// 	uint256 internal constant MAX_WITHDRAWAL_STACK_SIZE = 32;

// 	/*///////////////////////////////////////////////////////////////
//                                 AUTH
//     //////////////////////////////////////////////////////////////*/

// 	event ManagerUpdate(address indexed account, bool isManager);
// 	event AllowedUpdate(address indexed account, bool isManager);
// 	event SetPublic(bool setPublic);

// 	modifier requiresAuth() {
// 		require(msg.sender == owner() || isManager(msg.sender), "Vault: NO_AUTH");
// 		_;
// 	}

// 	mapping(address => bool) private _allowed;

// 	// Allowed (allow list for deposits)

// 	function isAllowed(address user) public view returns (bool) {
// 		return user == owner() || isManager(user) || _allowed[user];
// 	}

// 	function setAllowed(address user, bool _isManager) external requiresAuth {
// 		_allowed[user] = _isManager;
// 		emit AllowedUpdate(user, _isManager);
// 	}

// 	function bulkAllow(address[] memory users) external requiresAuth {
// 		for (uint256 i; i < users.length; i++) {
// 			_allowed[users[i]] = true;
// 			emit AllowedUpdate(users[i], true);
// 		}
// 	}

// 	modifier requireAllow() {
// 		require(_isPublic || isAllowed(msg.sender), "Vault: NOT_ON_ALLOW_LIST");
// 		_;
// 	}

// 	mapping(address => bool) private _managers;

// 	// GOVERNANCE - MANAGER
// 	function isManager(address user) public view returns (bool) {
// 		return _managers[user];
// 	}

// 	function setManager(address user, bool _isManager) public onlyOwner {
// 		_managers[user] = _isManager;
// 		emit ManagerUpdate(user, _isManager);
// 	}

// 	function isPublic() external view returns (bool) {
// 		return _isPublic;
// 	}

// 	function setPublic(bool isPublic_) external requiresAuth {
// 		_isPublic = isPublic_;
// 		emit SetPublic(isPublic_);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                            FEE CONFIGURATION
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice The percentage of profit recognized each harvest to reserve as fees.
// 	/// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
// 	uint256 public feePercent;

// 	/// @notice Emitted when the fee percentage is updated.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newFeePercent The new fee percentage.
// 	event FeePercentUpdated(address indexed user, uint256 newFeePercent);

// 	/// @notice Sets a new fee percentage.
// 	/// @param newFeePercent The new fee percentage.
// 	function setFeePercent(uint256 newFeePercent) public onlyOwner {
// 		// A fee percentage over 100% doesn't make sense.
// 		require(newFeePercent <= 1e18, "FEE_TOO_HIGH");

// 		// Update the fee percentage.
// 		feePercent = newFeePercent;

// 		emit FeePercentUpdated(msg.sender, newFeePercent);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                         HARVEST CONFIGURATION
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted when the harvest window is updated.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newHarvestWindow The new harvest window.
// 	event HarvestWindowUpdated(address indexed user, uint128 newHarvestWindow);

// 	/// @notice Emitted when the harvest delay is updated.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newHarvestDelay The new harvest delay.
// 	event HarvestDelayUpdated(address indexed user, uint64 newHarvestDelay);

// 	/// @notice Emitted when the harvest delay is scheduled to be updated next harvest.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newHarvestDelay The scheduled updated harvest delay.
// 	event HarvestDelayUpdateScheduled(address indexed user, uint64 newHarvestDelay);

// 	/// @notice The period in seconds during which multiple harvests can occur
// 	/// regardless if they are taking place before the harvest delay has elapsed.
// 	/// @dev Long harvest windows open the Vault up to profit distribution slowdown attacks.
// 	uint128 public harvestWindow;

// 	/// @notice The period in seconds over which locked profit is unlocked.
// 	/// @dev Cannot be 0 as it opens harvests up to sandwich attacks.
// 	uint64 public harvestDelay;

// 	/// @notice The value that will replace harvestDelay next harvest.
// 	/// @dev In the case that the next delay is 0, no update will be applied.
// 	uint64 public nextHarvestDelay;

// 	/// @notice Sets a new harvest window.
// 	/// @param newHarvestWindow The new harvest window.
// 	/// @dev The Vault's harvestDelay must already be set before calling.
// 	function setHarvestWindow(uint128 newHarvestWindow) public onlyOwner {
// 		// A harvest window longer than the harvest delay doesn't make sense.
// 		require(newHarvestWindow <= harvestDelay, "WINDOW_TOO_LONG");

// 		// Update the harvest window.
// 		harvestWindow = newHarvestWindow;

// 		emit HarvestWindowUpdated(msg.sender, newHarvestWindow);
// 	}

// 	/// @notice Sets a new harvest delay.
// 	/// @param newHarvestDelay The new harvest delay to set.
// 	/// @dev If the current harvest delay is 0, meaning it has not
// 	/// been set before, it will be updated immediately, otherwise
// 	/// it will be scheduled to take effect after the next harvest.
// 	function setHarvestDelay(uint64 newHarvestDelay) public onlyOwner {
// 		// A harvest delay of 0 makes harvests vulnerable to sandwich attacks.
// 		require(newHarvestDelay != 0, "DELAY_CANNOT_BE_ZERO");

// 		// A harvest delay longer than 1 year doesn't make sense.
// 		require(newHarvestDelay <= 365 days, "DELAY_TOO_LONG");

// 		// If the harvest delay is 0, meaning it has not been set before:
// 		if (harvestDelay == 0) {
// 			// We'll apply the update immediately.
// 			harvestDelay = newHarvestDelay;

// 			emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
// 		} else {
// 			// We'll apply the update next harvest.
// 			nextHarvestDelay = newHarvestDelay;

// 			emit HarvestDelayUpdateScheduled(msg.sender, newHarvestDelay);
// 		}
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                        TARGET FLOAT CONFIGURATION
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice The desired percentage of the Vault's holdings to keep as float.
// 	/// @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
// 	uint256 public targetFloatPercent;

// 	/// @notice Emitted when the target float percentage is updated.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newTargetFloatPercent The new target float percentage.
// 	event TargetFloatPercentUpdated(address indexed user, uint256 newTargetFloatPercent);

// 	/// @notice Set a new target float percentage.
// 	/// @param newTargetFloatPercent The new target float percentage.
// 	function setTargetFloatPercent(uint256 newTargetFloatPercent) external onlyOwner {
// 		// A target float percentage over 100% doesn't make sense.
// 		require(newTargetFloatPercent <= 1e18, "TARGET_TOO_HIGH");

// 		// Update the target float percentage.
// 		targetFloatPercent = newTargetFloatPercent;

// 		emit TargetFloatPercentUpdated(msg.sender, newTargetFloatPercent);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                    UNDERLYING IS WETH CONFIGURATION
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Whether the Vault should treat the underlying token as WETH compatible.
// 	/// @dev If enabled the Vault will allow trusting strategies that accept Ether.
// 	bool public underlyingIsWETH;

// 	/// @notice Emitted when whether the Vault should treat the underlying as WETH is updated.
// 	/// @param user The authorized user who triggered the update.
// 	/// @param newUnderlyingIsWETH Whether the Vault nows treats the underlying as WETH.
// 	event UnderlyingIsWETHUpdated(address indexed user, bool newUnderlyingIsWETH);

// 	/// @notice Sets whether the Vault treats the underlying as WETH.
// 	/// @param newUnderlyingIsWETH Whether the Vault should treat the underlying as WETH.
// 	/// @dev The underlying token must have 18 decimals, to match Ether's decimal scheme.
// 	function setUnderlyingIsWETH(bool newUnderlyingIsWETH) external onlyOwner {
// 		// Ensure the underlying token's decimals match ETH.
// 		require(
// 			!newUnderlyingIsWETH || ERC20(address(UNDERLYING)).decimals() == 18,
// 			"WRONG_DECIMALS"
// 		);

// 		// Update whether the Vault treats the underlying as WETH.
// 		underlyingIsWETH = newUnderlyingIsWETH;

// 		emit UnderlyingIsWETHUpdated(msg.sender, newUnderlyingIsWETH);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                           STRATEGY STORAGE
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
// 	/// @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
// 	uint256 public totalStrategyHoldings;

// 	/// @dev Packed struct of strategy data.
// 	/// @param trusted Whether the strategy is trusted.
// 	/// @param balance The amount of underlying tokens held in the strategy.
// 	struct StrategyData {
// 		// Used to determine if the Vault will operate on a strategy.
// 		bool trusted;
// 		// Used to determine profit and loss during harvests of the strategy.
// 		uint248 balance;
// 	}

// 	/// @notice Maps strategies to data the Vault holds on them.
// 	mapping(Strategy => StrategyData) public getStrategyData;

// 	/*///////////////////////////////////////////////////////////////
//                              HARVEST STORAGE
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
// 	/// @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
// 	uint64 public lastHarvestWindowStart;

// 	/// @notice A timestamp representing when the most recent harvest occurred.
// 	uint64 public lastHarvest;

// 	/// @notice The amount of locked profit at the end of the last harvest.
// 	uint128 public maxLockedProfit;

// 	/*///////////////////////////////////////////////////////////////
//                         WITHDRAWAL QUEUE STORAGE
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice An ordered array of strategies representing the withdrawal queue.
// 	/// @dev The queue is processed in descending order, meaning the last index will be withdrawn from first.
// 	/// @dev Strategies that are untrusted, duplicated, or have no balance are filtered out when encountered at
// 	/// withdrawal time, not validated upfront, meaning the queue may not reflect the "true" set used for withdrawals.
// 	Strategy[] public withdrawalQueue;

// 	/// @notice Gets the full withdrawal queue.
// 	/// @return An ordered array of strategies representing the withdrawal queue.
// 	/// @dev This is provided because Solidity converts public arrays into index getters,
// 	/// but we need a way to allow external contracts and users to access the whole array.
// 	function getWithdrawalQueue() external view returns (Strategy[] memory) {
// 		return withdrawalQueue;
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                         DEPOSIT/WITHDRAWAL LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted after a successful deposit.
// 	/// @param user The address that deposited into the Vault.
// 	/// @param underlyingAmount The amount of underlying tokens that were deposited.
// 	event Deposit(address indexed user, uint256 underlyingAmount);

// 	/// @notice Emitted after a successful withdrawal.
// 	/// @param user The address that withdrew from the Vault.
// 	/// @param underlyingAmount The amount of underlying tokens that were withdrawn.
// 	event Withdraw(address indexed user, uint256 underlyingAmount);

// 	/// @notice Deposit a specific amount of underlying tokens.
// 	/// @param underlyingAmount The amount of the underlying token to deposit.
// 	function deposit(uint256 underlyingAmount) external requireAllow {
// 		// you should not be able to deposit funds over the tvl limit
// 		require(underlyingAmount + totalHoldings() <= getMaxTvl(), "OVER_MAX_TVL");

// 		bool isFirstDeposit = totalSupply() == 0;

// 		// Determine the equivalent amount of rvTokens and mint them.
// 		// use deposit lock here (add locked loss to inflate share price)
// 		_mint(msg.sender, underlyingAmount.fdiv(exchangeRateLock(PnlLock.Deposit), BASE_UNIT));

// 		// mint MINIMUM_LIQUIDITY if this is the first deposit and lock it
// 		// using address(1) because erc20 implementation prevents using 0
// 		if (isFirstDeposit) _mint(address(1), MINIMUM_LIQUIDITY);

// 		emit Deposit(msg.sender, underlyingAmount);

// 		// Transfer in underlying tokens from the user.
// 		// This will revert if the user does not have the amount specified.
// 		UNDERLYING.safeTransferFrom(msg.sender, address(this), underlyingAmount);
// 	}

// 	/// @notice Withdraw a specific amount of underlying tokens.
// 	/// @param underlyingAmount The amount of underlying tokens to withdraw.
// 	function withdraw(uint256 underlyingAmount) external nonReentrant {
// 		// Determine the equivalent amount of rvTokens and burn them.
// 		// This will revert if the user does not have enough rvTokens.
// 		// use withdraw lock (subtrackt lockedProfits do deflate share price)
// 		_burn(msg.sender, underlyingAmount.fdiv(exchangeRateLock(PnlLock.Withdraw), BASE_UNIT));

// 		emit Withdraw(msg.sender, underlyingAmount);

// 		// Withdraw from strategies if needed and transfer.
// 		transferUnderlyingTo(msg.sender, underlyingAmount);
// 	}

// 	/// @notice Redeem a specific amount of rvTokens for underlying tokens.
// 	/// @param rvTokenAmount The amount of rvTokens to redeem for underlying tokens.
// 	function redeem(uint256 rvTokenAmount) external nonReentrant {
// 		// Determine the equivalent amount of underlying tokens.
// 		uint256 underlyingAmount = rvTokenAmount.fmul(
// 			exchangeRateLock(PnlLock.Withdraw),
// 			BASE_UNIT
// 		);

// 		// Burn the provided amount of rvTokens.
// 		// This will revert if the user does not have enough rvTokens.
// 		_burn(msg.sender, rvTokenAmount);

// 		emit Withdraw(msg.sender, underlyingAmount);
// 		// Withdraw from strategies if needed and transfer.
// 		transferUnderlyingTo(msg.sender, underlyingAmount);
// 	}

// 	/// @dev Transfers a specific amount of underlying tokens held in strategies and/or float to a recipient.
// 	/// @dev Only withdraws from strategies if needed and maintains the target float percentage if possible.
// 	/// @param recipient The user to transfer the underlying tokens to.
// 	/// @param underlyingAmount The amount of underlying tokens to transfer.
// 	function transferUnderlyingTo(address recipient, uint256 underlyingAmount) internal {
// 		// Get the Vault's floating balance.
// 		uint256 float = totalFloat();

// 		// If the amount is greater than the float, withdraw from strategies.
// 		if (underlyingAmount > float) {
// 			// Compute the amount needed to reach our target float percentage.
// 			// use withdraw lock here because we're withdrawing
// 			uint256 floatMissingForTarget = (totalHoldingsLock(PnlLock.Withdraw) - underlyingAmount)
// 				.fmul(targetFloatPercent, 1e18);

// 			// Compute the bare minimum amount we need for this withdrawal.
// 			uint256 floatMissingForWithdrawal = underlyingAmount - float;

// 			// Pull enough to cover the withdrawal and reach our target float percentage.
// 			pullFromWithdrawalQueue(floatMissingForWithdrawal + floatMissingForTarget, float);
// 		}

// 		// Transfer the provided amount of underlying tokens.
// 		UNDERLYING.safeTransfer(recipient, underlyingAmount);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                         VAULT ACCOUNTING LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Returns a user's Vault balance in underlying tokens.
// 	/// @param user The user to get the underlying balance of.
// 	/// @return The user's Vault balance in underlying tokens.
// 	function balanceOfUnderlying(address user) external view returns (uint256) {
// 		return balanceOf(user).fmul(exchangeRateLock(PnlLock.Withdraw), BASE_UNIT);
// 	}

// 	/// @notice Returns the amount of underlying tokens an rvToken can be redeemed for.
// 	/// @return The amount of underlying tokens an rvToken can be redeemed for.
// 	function exchangeRate() public view returns (uint256) {
// 		return exchangeRateLock(PnlLock.None);
// 	}

// 	/// @notice Returns the amount of underlying tokens an rvToken can be redeemed for.
// 	/// @return The amount of underlying tokens an rvToken can be redeemed for.
// 	function exchangeRateLock(PnlLock lock) public view returns (uint256) {
// 		// Get the total supply of rvTokens.
// 		uint256 rvTokenSupply = totalSupply();

// 		// If there are no rvTokens in circulation, return an exchange rate of 1:1.
// 		if (rvTokenSupply == 0) {
// 			return BASE_UNIT + MINIMUM_LIQUIDITY;
// 		}

// 		// Calculate the exchange rate by dividing the total holdings by the rvToken supply.
// 		return totalHoldingsLock(lock).fdiv(rvTokenSupply, BASE_UNIT);
// 	}

// 	/// @notice Calculates the total amount of underlying tokens the Vault holds.
// 	/// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
// 	function totalHoldings() public view returns (uint256) {
// 		return totalHoldingsLock(PnlLock.None);
// 	}

// 	/// @notice Calculates the total amount of underlying tokens the Vault holds.
// 	/// @return totalUnderlyingHeld The total amount of underlying tokens the Vault holds.
// 	function totalHoldingsLock(PnlLock lock) public view returns (uint256 totalUnderlyingHeld) {
// 		unchecked {
// 			// this could overflow - in this case withdraw should not be possible anyway
// 			if (lock == PnlLock.None)
// 				return totalStrategyHoldings - lossSinceHarvest() + totalFloat();
// 		}

// 		(uint256 lockedProfit_, uint256 lockedLoss_) = lockedProfit();
// 		// this could overflow - in this case withdraw should not be possible anyway
// 		if (lock == PnlLock.Withdraw)
// 			return totalStrategyHoldings - lockedProfit_ - lossSinceHarvest() + totalFloat();

// 		unchecked {
// 			// Cannot underflow as locked profit can't exceed total strategy holdings.
// 			// inflate the total holdings by lockedLoss as a saftey measure
// 			if (lock == PnlLock.Deposit) return totalStrategyHoldings + lockedLoss_ + totalFloat();
// 		}
// 	}

// 	/// @notice Calculates the current amount of locked profit.
// 	/// @return The current amount of locked profit.

// 	/// @notice Calculates the current amount of locked profit.
// 	/// @return The current amount of locked profit.
// 	function lockedProfit() public view returns (uint256, uint256) {
// 		// Get the last harvest and harvest delay.
// 		uint256 previousHarvest = lastHarvest;
// 		uint256 harvestInterval = harvestDelay;

// 		unchecked {
// 			// If the harvest delay has passed, there is no locked profit.
// 			// Cannot overflow on human timescales since harvestInterval is capped.
// 			if (block.timestamp >= previousHarvest + harvestInterval) return (0, 0);

// 			// Get the maximum amount we could return.
// 			uint256 maximumLockedProfit = maxLockedProfit;
// 			uint256 maximumLockedLoss = maxLockedLoss;

// 			// Compute how much profit remains locked based on the last harvest and harvest delay.
// 			// It's impossible for the previous harvest to be in the future, so this will never underflow.
// 			return (
// 				maximumLockedProfit -
// 					(maximumLockedProfit * (block.timestamp - previousHarvest)) /
// 					harvestInterval,
// 				maximumLockedLoss -
// 					(maximumLockedLoss * (block.timestamp - previousHarvest)) /
// 					harvestInterval
// 			);
// 		}
// 	}

// 	/// @notice Returns the amount of underlying tokens that idly sit in the Vault.
// 	/// @return The amount of underlying tokens that sit idly in the Vault.
// 	function totalFloat() public view returns (uint256) {
// 		return UNDERLYING.balanceOf(address(this));
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                              HARVEST LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted after a successful harvest.
// 	/// @param user The authorized user who triggered the harvest.
// 	/// @param strategies The trusted strategies that were harvested.
// 	event Harvest(address indexed user, Strategy[] strategies);

// 	/// @notice Harvest a set of trusted strategies.
// 	/// @param strategies The trusted strategies to harvest.
// 	/// @dev Will always revert if called outside of an active
// 	/// harvest window or before the harvest delay has passed.
// 	function harvest(Strategy[] calldata strategies) external requiresAuth {
// 		// If this is the first harvest after the last window:
// 		if (block.timestamp >= lastHarvest + harvestDelay) {
// 			// Set the harvest window's start timestamp.
// 			// Cannot overflow 64 bits on human timescales.
// 			lastHarvestWindowStart = uint64(block.timestamp);
// 		} else {
// 			// We know this harvest is not the first in the window so we need to ensure it's within it.
// 			require(block.timestamp <= lastHarvestWindowStart + harvestWindow, "BAD_HARVEST_TIME");
// 		}

// 		// Get the Vault's current total strategy holdings.
// 		uint256 oldTotalStrategyHoldings = totalStrategyHoldings;

// 		// Used to store the total profit accrued by the strategies.
// 		uint256 totalProfitAccrued;
// 		uint256 totalLoss;

// 		// Used to store the new total strategy holdings after harvesting.
// 		uint256 newTotalStrategyHoldings = oldTotalStrategyHoldings;

// 		// Will revert if any of the specified strategies are untrusted.
// 		for (uint256 i = 0; i < strategies.length; i++) {
// 			// Get the strategy at the current index.
// 			Strategy strategy = strategies[i];

// 			// If an untrusted strategy could be harvested a malicious user could use
// 			// a fake strategy that over-reports holdings to manipulate the exchange rate.
// 			require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

// 			// Get the strategy's previous and current balance.
// 			uint256 balanceLastHarvest = getStrategyData[strategy].balance;
// 			uint256 balanceThisHarvest = strategy.balanceOfUnderlying(address(this));

// 			// Update the strategy's stored balance. Cast overflow is unrealistic.
// 			getStrategyData[strategy].balance = balanceThisHarvest.safeCastTo248();

// 			// Increase/decrease newTotalStrategyHoldings based on the profit/loss registered.
// 			// We cannot wrap the subtraction in parenthesis as it would underflow if the strategy had a loss.
// 			newTotalStrategyHoldings =
// 				newTotalStrategyHoldings +
// 				balanceThisHarvest -
// 				balanceLastHarvest;

// 			unchecked {
// 				// Update the total profit accrued while counting losses as zero profit.
// 				// Cannot overflow as we already increased total holdings without reverting.
// 				if (balanceThisHarvest > balanceLastHarvest) {
// 					totalProfitAccrued += balanceThisHarvest - balanceLastHarvest; // Profits since last harvest.
// 				} else {
// 					// If the strategy registered a net loss we add it to totalLoss.
// 					totalLoss += balanceLastHarvest - balanceThisHarvest;
// 				}
// 			}
// 		}

// 		// Compute fees as the fee percent multiplied by the profit.
// 		uint256 feesAccrued = totalProfitAccrued.fmul(feePercent, 1e18);

// 		// If we accrued any fees, mint an equivalent amount of rvTokens.
// 		// Authorized users can claim the newly minted rvTokens via claimFees.
// 		_mint(address(this), feesAccrued.fdiv(exchangeRate(), BASE_UNIT));

// 		// Update max unlocked profit based on any remaining locked profit plus new profit.
// 		(uint256 lockedProfit_, uint256 lockedLoss_) = lockedProfit();
// 		maxLockedProfit = (lockedProfit_ + totalProfitAccrued - feesAccrued).safeCastTo128();
// 		maxLockedLoss = (lockedLoss_ + totalLoss).safeCastTo128();

// 		// Set strategy holdings to our new total.
// 		totalStrategyHoldings = newTotalStrategyHoldings;

// 		// Update the last harvest timestamp.
// 		// Cannot overflow on human timescales.
// 		lastHarvest = uint64(block.timestamp);

// 		emit Harvest(msg.sender, strategies);

// 		// Get the next harvest delay.
// 		uint64 newHarvestDelay = nextHarvestDelay;

// 		// If the next harvest delay is not 0:
// 		if (newHarvestDelay != 0) {
// 			// Update the harvest delay.
// 			harvestDelay = newHarvestDelay;

// 			// Reset the next harvest delay.
// 			nextHarvestDelay = 0;

// 			emit HarvestDelayUpdated(msg.sender, newHarvestDelay);
// 		}
// 	}

// 	/// @notice Compute total for the strategies since last harvest.
// 	/// @dev It is necessary to include this when computing the withdrawal exchange rate
// 	function lossSinceHarvest() internal view returns (uint256 loss) {
// 		uint256 totalCurrentHoldings;
// 		// use this instead of totalStrategyHoldings because some strategies with balances may not be in queue
// 		uint256 balanceInQueue;

// 		// this assumes all strategies with balance are in the withdrawal queue
// 		for (uint256 i = 0; i < withdrawalQueue.length; i++) {
// 			// Get the strategy at the current index.
// 			Strategy strategy = withdrawalQueue[i];

// 			// If an untrusted strategy could be harvested a malicious user could use
// 			if (!getStrategyData[strategy].trusted || getStrategyData[strategy].balance == 0)
// 				continue;

// 			balanceInQueue = balanceInQueue + getStrategyData[strategy].balance;

// 			totalCurrentHoldings =
// 				totalCurrentHoldings +
// 				strategy.balanceOfUnderlying(address(this));
// 		}

// 		// Update strategy holdings
// 		loss = balanceInQueue > totalCurrentHoldings ? balanceInQueue - totalCurrentHoldings : 0;
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                     MAX TVL LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	function getMaxTvl() public view returns (uint256 maxTvl) {
// 		return min(_maxTvl, _stratMaxTvl);
// 	}

// 	event MaxTvlUpdated(uint256 maxTvl);

// 	function setMaxTvl(uint256 maxTvl_) public requiresAuth {
// 		_maxTvl = maxTvl_;
// 		emit MaxTvlUpdated(min(_maxTvl, _stratMaxTvl));
// 	}

// 	// TODO should this just be a view computed on demand?
// 	function updateStratTvl() public requiresAuth returns (uint256 maxTvl) {
// 		for (uint256 i; i < withdrawalQueue.length; i++) {
// 			Strategy strategy = withdrawalQueue[i];
// 			uint256 stratTvl = strategy.getMaxTvl();
// 			// don't let new max overflow
// 			unchecked {
// 				maxTvl = maxTvl > maxTvl + stratTvl ? maxTvl : maxTvl + stratTvl;
// 			}
// 		}
// 		_stratMaxTvl = maxTvl;
// 		emit MaxTvlUpdated(min(_maxTvl, _stratMaxTvl));
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                     STRATEGY DEPOSIT/WITHDRAWAL LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted after the Vault deposits into a strategy contract.
// 	/// @param user The authorized user who triggered the deposit.
// 	/// @param strategy The strategy that was deposited into.
// 	/// @param underlyingAmount The amount of underlying tokens that were deposited.
// 	event StrategyDeposit(
// 		address indexed user,
// 		Strategy indexed strategy,
// 		uint256 underlyingAmount
// 	);

// 	/// @notice Emitted after the Vault withdraws funds from a strategy contract.
// 	/// @param user The authorized user who triggered the withdrawal.
// 	/// @param strategy The strategy that was withdrawn from.
// 	/// @param underlyingAmount The amount of underlying tokens that were withdrawn.
// 	event StrategyWithdrawal(
// 		address indexed user,
// 		Strategy indexed strategy,
// 		uint256 underlyingAmount
// 	);

// 	/// @notice Deposit a specific amount of float into a trusted strategy.
// 	/// @param strategy The trusted strategy to deposit into.
// 	/// @param underlyingAmount The amount of underlying tokens in float to deposit.
// 	function depositIntoStrategy(Strategy strategy, uint256 underlyingAmount) public requiresAuth {
// 		// A strategy must be trusted before it can be deposited into.
// 		require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

// 		// We don't allow depositing 0 to prevent emitting a useless event.
// 		require(underlyingAmount != 0, "AMOUNT_CANNOT_BE_ZERO");

// 		emit StrategyDeposit(msg.sender, strategy, underlyingAmount);

// 		// Increase totalStrategyHoldings to account for the deposit.
// 		totalStrategyHoldings += underlyingAmount;
// 		unchecked {
// 			// Without this the next harvest would count the deposit as profit.
// 			// Cannot overflow as the balance of one strategy can't exceed the sum of all.
// 			getStrategyData[strategy].balance += underlyingAmount.safeCastTo248();
// 		}

// 		// We need to deposit differently if the strategy takes ETH.
// 		if (strategy.isCEther()) {
// 			// Unwrap the right amount of WETH.
// 			IWETH(payable(address(UNDERLYING))).withdraw(underlyingAmount);

// 			// Deposit into the strategy and assume it will revert on error.
// 			ETHStrategy(address(strategy)).mint{ value: underlyingAmount }();
// 		} else {
// 			// Approve underlyingAmount to the strategy so we can deposit.
// 			UNDERLYING.safeApprove(address(strategy), underlyingAmount);

// 			// Deposit into the strategy and revert if it returns an error code.
// 			require(ERC20Strategy(address(strategy)).mint(underlyingAmount) == 0, "MINT_FAILED");
// 		}
// 	}

// 	/// @notice Withdraw a specific amount of underlying tokens from a strategy.
// 	/// @param strategy The strategy to withdraw from.
// 	/// @param underlyingAmount  The amount of underlying tokens to withdraw.
// 	/// @dev Withdrawing from a strategy will not remove it from the withdrawal queue.
// 	function withdrawFromStrategy(Strategy strategy, uint256 underlyingAmount)
// 		public
// 		requiresAuth
// 		nonReentrant
// 	{
// 		// A strategy must be trusted before it can be withdrawn from.
// 		require(getStrategyData[strategy].trusted, "UNTRUSTED_STRATEGY");

// 		// We don't allow withdrawing 0 to prevent emitting a useless event.
// 		require(underlyingAmount != 0, "AMOUNT_CANNOT_BE_ZERO");

// 		// Without this the next harvest would count the withdrawal as a loss.
// 		getStrategyData[strategy].balance -= underlyingAmount.safeCastTo248();

// 		unchecked {
// 			// Decrease totalStrategyHoldings to account for the withdrawal.
// 			// Cannot underflow as the balance of one strategy will never exceed the sum of all.
// 			totalStrategyHoldings -= underlyingAmount;
// 		}

// 		emit StrategyWithdrawal(msg.sender, strategy, underlyingAmount);

// 		// Withdraw from the strategy and revert if it returns an error code.
// 		require(strategy.redeemUnderlying(underlyingAmount) == 0, "REDEEM_FAILED");

// 		// Wrap the withdrawn Ether into WETH if necessary.
// 		if (strategy.isCEther())
// 			IWETH(payable(address(UNDERLYING))).deposit{ value: underlyingAmount }();
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                       STRATEGY TRUST/DISTRUST LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted when a strategy is set to trusted.
// 	/// @param user The authorized user who trusted the strategy.
// 	/// @param strategy The strategy that became trusted.
// 	event StrategyTrusted(address indexed user, Strategy indexed strategy);

// 	/// @notice Emitted when a strategy is set to untrusted.
// 	/// @param user The authorized user who untrusted the strategy.
// 	/// @param strategy The strategy that became untrusted.
// 	event StrategyDistrusted(address indexed user, Strategy indexed strategy);

// 	/// @notice Helper method to add strategy and push it to the que in one tx.
// 	/// @param strategy The strategy to add.
// 	function addStrategy(Strategy strategy) public onlyOwner {
// 		trustStrategy(strategy);
// 		pushToWithdrawalQueue(strategy);
// 		updateStratTvl();
// 	}

// 	/// @notice Helper method to migrate strategy to a new implementation.
// 	/// @param prevStrategy The strategy to remove.
// 	/// @param newStrategy The strategy to add.
// 	// slither-disable-next-line reentrancy-eth
// 	function migrateStrategy(
// 		Strategy prevStrategy,
// 		Strategy newStrategy,
// 		uint256 queueIndex
// 	) public onlyOwner {
// 		trustStrategy(newStrategy);

// 		if (queueIndex < withdrawalQueue.length)
// 			replaceWithdrawalQueueIndex(queueIndex, newStrategy);
// 		else pushToWithdrawalQueue(newStrategy);

// 		// make sure to call harvest before migrate
// 		uint256 stratBalance = getStrategyData[prevStrategy].balance;
// 		if (stratBalance > 0) {
// 			withdrawFromStrategy(prevStrategy, stratBalance);
// 			depositIntoStrategy(
// 				newStrategy,
// 				// we may end up with slightly less balance because of tx costs
// 				min(UNDERLYING.balanceOf(address(this)), stratBalance)
// 			);
// 		}
// 		distrustStrategy(prevStrategy);
// 	}

// 	/// @notice Stores a strategy as trusted, enabling it to be harvested.
// 	/// @param strategy The strategy to make trusted.
// 	function trustStrategy(Strategy strategy) public onlyOwner {
// 		// Ensure the strategy accepts the correct underlying token.
// 		// If the strategy accepts ETH the Vault should accept WETH, it'll handle wrapping when necessary.
// 		require(
// 			strategy.isCEther()
// 				? underlyingIsWETH
// 				: ERC20Strategy(address(strategy)).underlying() == UNDERLYING,
// 			"WRONG_UNDERLYING"
// 		);

// 		// Store the strategy as trusted.
// 		getStrategyData[strategy].trusted = true;

// 		emit StrategyTrusted(msg.sender, strategy);
// 	}

// 	/// @notice Stores a strategy as untrusted, disabling it from being harvested.
// 	/// @param strategy The strategy to make untrusted.
// 	function distrustStrategy(Strategy strategy) public onlyOwner {
// 		// Store the strategy as untrusted.
// 		getStrategyData[strategy].trusted = false;

// 		emit StrategyDistrusted(msg.sender, strategy);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                          SEIZE STRATEGY LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted after a strategy is seized.
// 	/// @param user The authorized user who triggered the seize.
// 	/// @param strategy The strategy that was seized.
// 	event StrategySeized(address indexed user, Strategy indexed strategy);

// 	/// @notice Seizes a strategy.
// 	/// @param strategy The strategy to seize.
// 	/// @dev Intended for use in emergencies or other extraneous situations where the
// 	/// strategy requires interaction outside of the Vault's standard operating procedures.
// 	function seizeStrategy(Strategy strategy, IERC20[] calldata tokens)
// 		external
// 		nonReentrant
// 		requiresAuth
// 	{
// 		// Get the strategy's last reported balance of underlying tokens.
// 		uint256 strategyBalance = getStrategyData[strategy].balance;

// 		// if there are any tokens left, transfer them to owner
// 		Strategy(strategy).emergencyWithdraw(owner(), tokens);

// 		// Set the strategy's balance to 0.
// 		getStrategyData[strategy].balance = 0;

// 		// If the strategy's balance exceeds the Vault's current
// 		// holdings, instantly unlock any remaining locked profit.
// 		// use Withdraw holdings because we want to subtract lockedProfits in check
// 		if (strategyBalance > totalHoldingsLock(PnlLock.Withdraw)) maxLockedProfit = 0;

// 		unchecked {
// 			// Decrease totalStrategyHoldings to account for the seize.
// 			// Cannot underflow as the balance of one strategy will never exceed the sum of all.
// 			totalStrategyHoldings -= strategyBalance;
// 		}

// 		emit StrategySeized(msg.sender, strategy);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                              FEE CLAIM LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @notice Emitted after fees are claimed.
// 	/// @param user The authorized user who claimed the fees.
// 	/// @param rvTokenAmount The amount of rvTokens that were claimed.
// 	event FeesClaimed(address indexed user, uint256 rvTokenAmount);

// 	/// @notice Claims fees accrued from harvests.
// 	/// @param rvTokenAmount The amount of rvTokens to claim.
// 	/// @dev Accrued fees are measured as rvTokens held by the Vault.
// 	function claimFees(uint256 rvTokenAmount) external requiresAuth {
// 		emit FeesClaimed(msg.sender, rvTokenAmount);

// 		// Transfer the provided amount of rvTokens to the caller.
// 		IERC20(address(this)).safeTransfer(msg.sender, rvTokenAmount);
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                           RECIEVE ETHER LOGIC
//     //////////////////////////////////////////////////////////////*/

// 	/// @dev Required for the Vault to receive unwrapped ETH.
// 	receive() external payable {}

// 	/**
// 	 * @dev Returns the smallest of two numbers.
// 	 */
// 	function min(uint256 a, uint256 b) internal pure returns (uint256) {
// 		return a < b ? a : b;
// 	}

// 	/*///////////////////////////////////////////////////////////////
//                           UPGRADE VARS
//     //////////////////////////////////////////////////////////////*/

// 	uint256 private _maxTvl;
// 	uint256 private _stratMaxTvl;
// 	bool private _isPublic;

// 	/// @notice The amount of locked profit at the end of the last harvest.
// 	uint128 public maxLockedLoss;

// 	enum PnlLock {
// 		None,
// 		Deposit,
// 		Withdraw
// 	}

// 	uint256 public version;
// }
