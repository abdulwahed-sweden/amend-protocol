// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAmendEngine
 * @notice Interface for AMEND Protocol investment engine
 * @dev Manages fund deployment from AmendVault to whitelisted destinations
 *
 * The Engine is the trusted intermediary between the Vault and external
 * investment destinations. It maintains strict accounting and enforces
 * the protocol's core invariant: NO FEE ON LOSS.
 *
 * Fund Flow:
 *   Vault --(invest)--> Engine --(deployFunds)--> Destinations
 *   Destinations --(recallFunds)--> Engine --(divest)--> Vault
 */
interface IAmendEngine {
    // ============ Events ============

    /// @notice Emitted when an address is added to the whitelist
    /// @param destination The address added to whitelist
    event WhitelistAdded(address indexed destination);

    /// @notice Emitted when an address is removed from the whitelist
    /// @param destination The address removed from whitelist
    event WhitelistRemoved(address indexed destination);

    /// @notice Emitted when funds are deployed to a destination
    /// @param destination The address receiving the funds
    /// @param amount The amount of assets deployed
    event FundsDeployed(address indexed destination, uint256 amount);

    /// @notice Emitted when funds are recalled from a destination
    /// @param destination The address funds were recalled from
    /// @param amount The amount of assets recalled
    event FundsRecalled(address indexed destination, uint256 amount);

    /// @notice Emitted during emergency recall of all funds from a destination
    /// @param destination The address funds were recalled from
    /// @param amount The amount of assets recalled
    event EmergencyRecall(address indexed destination, uint256 amount);

    /// @notice Emitted when profit is settled with the Vault
    /// @param profitAmount The amount of profit reported
    event ProfitSettled(uint256 profitAmount);

    /// @notice Emitted when loss is settled with the Vault
    /// @param lossAmount The amount of loss reported
    event LossSettled(uint256 lossAmount);

    // Note: Paused and Unpaused events are inherited from OpenZeppelin's Pausable

    // ============ Errors ============

    /// @notice Thrown when attempting to deploy to a non-whitelisted address
    /// @param destination The non-whitelisted address
    error NotWhitelisted(address destination);

    /// @notice Thrown when attempting to whitelist an already whitelisted address
    /// @param destination The already whitelisted address
    error AlreadyWhitelisted(address destination);

    /// @notice Thrown when attempting to remove from whitelist with deployed funds
    /// @param destination The destination with deployed funds
    /// @param deployedAmount The amount currently deployed
    error CannotRemoveWithDeployedFunds(address destination, uint256 deployedAmount);

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when requesting more than available balance
    /// @param requested The amount requested
    /// @param available The amount available
    error InsufficientBalance(uint256 requested, uint256 available);

    /// @notice Thrown when recall exceeds deployed amount
    /// @param destination The destination address
    /// @param requested The amount requested to recall
    /// @param deployedAmount The amount currently deployed
    error RecallExceedsDeployed(address destination, uint256 requested, uint256 deployedAmount);

    /// @notice Thrown when contract is paused
    error ContractPaused();

    /// @notice Thrown when zero address is provided
    error ZeroAddress();

    /// @notice Thrown when there's nothing to settle
    error NothingToSettle();

    /// @notice Thrown when profit is not backed by actual asset balance
    /// @param profit The profit amount attempted
    /// @param balance The actual balance available
    error ProfitNotBacked(uint256 profit, uint256 balance);

    // ============ Admin Functions ============

    /**
     * @notice Add an address to the whitelist of allowed investment destinations
     * @dev Only callable by addresses with ADMIN_ROLE
     * @param destination The address to whitelist
     */
    function addToWhitelist(address destination) external;

    /**
     * @notice Remove an address from the whitelist
     * @dev Only callable by addresses with ADMIN_ROLE
     * @dev Cannot remove if funds are still deployed to destination
     * @param destination The address to remove from whitelist
     */
    function removeFromWhitelist(address destination) external;

    /**
     * @notice Pause all fund movements in case of emergency
     * @dev Only callable by addresses with ADMIN_ROLE
     */
    function pause() external;

    /**
     * @notice Resume normal operations after a pause
     * @dev Only callable by addresses with ADMIN_ROLE
     */
    function unpause() external;

    // ============ Manager Functions ============

    /**
     * @notice Deploy funds from Engine to a whitelisted destination
     * @dev Only callable by addresses with MANAGER_ROLE
     * @dev Pulls funds from Vault via invest(), then transfers to destination
     * @param destination The whitelisted address to receive funds
     * @param amount The amount of assets to deploy
     */
    function deployFunds(address destination, uint256 amount) external;

    /**
     * @notice Recall funds from a destination back to the Engine
     * @dev Only callable by addresses with MANAGER_ROLE
     * @dev Destination must have approved Engine to transfer, or use push pattern
     * @param destination The address to recall funds from
     * @param amount The amount of assets to recall
     */
    function recallFunds(address destination, uint256 amount) external;

    /**
     * @notice Emergency recall of all funds from a destination
     * @dev Callable by ADMIN_ROLE or MANAGER_ROLE
     * @dev Attempts to recall all deployed funds from destination
     * @param destination The address to recall all funds from
     */
    function emergencyRecall(address destination) external;

    // ============ Reporter Functions ============

    /**
     * @notice Settle profit with the Vault
     * @dev Only callable by addresses with REPORTER_ROLE
     * @dev Profit must be backed by actual assets in Engine
     * @dev Transfers profit to Vault, then calls reportProfit()
     * @param profitAmount The amount of profit to report
     */
    function settleProfit(uint256 profitAmount) external;

    /**
     * @notice Settle loss with the Vault
     * @dev Only callable by addresses with REPORTER_ROLE
     * @dev Calls reportLoss() on Vault to adjust NAV (NO FEE)
     * @param lossAmount The amount of loss to report
     */
    function settleLoss(uint256 lossAmount) external;

    // ============ View Functions ============

    /**
     * @notice Get the amount of assets deployed to a specific destination
     * @param destination The destination address to query
     * @return The amount of assets deployed to the destination
     */
    function getDeployedTo(address destination) external view returns (uint256);

    /**
     * @notice Get the total amount of assets deployed across all destinations
     * @return The total deployed amount
     */
    function getTotalDeployed() external view returns (uint256);

    /**
     * @notice Check if an address is on the whitelist
     * @param destination The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function isWhitelisted(address destination) external view returns (bool);

    /**
     * @notice Get the underlying asset address (USDC)
     * @return The asset token address
     */
    function asset() external view returns (address);

    /**
     * @notice Get the linked AmendVault address
     * @return The vault address
     */
    function vault() external view returns (address);

    /**
     * @notice Check if the contract is currently paused
     * @return True if paused, false otherwise
     */
    function isPaused() external view returns (bool);
}
