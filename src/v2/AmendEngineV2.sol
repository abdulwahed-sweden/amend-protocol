// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IAmendVaultV2} from "./interfaces/IAmendVaultV2.sol";

/**
 * @title AmendEngineV2
 * @author Abdulwahed Mansour
 * @notice Strategy manager for AMEND Protocol v2
 * @dev Implements atomic settlement with Vault (Vault Pulls Always)
 *
 * Key Changes from v0.1.1:
 * - finalizeTrade() replaces recallFunds() + settleProfit()
 * - EMERGENCY_ROLE separated from ADMIN for pause control
 * - Vault pulls funds atomically via approve pattern
 */
contract AmendEngineV2 is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Roles ============
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ============ Immutables ============
    IAmendVaultV2 public immutable VAULT;
    IERC20 public immutable ASSET;

    // ============ State Variables ============
    mapping(address => bool) private _whitelist;
    mapping(address => uint256) private _deployed;
    uint256 private _totalDeployed;

    // ============ Events ============
    event WhitelistAdded(address indexed destination);
    event WhitelistRemoved(address indexed destination);
    event FundsDeployed(address indexed destination, uint256 amount);
    event FundsRecalled(address indexed destination, uint256 amount);
    event TradeFinalized(uint256 principal, uint256 profit);
    event LossReported(uint256 loss);
    event EmergencyRecall(address indexed destination, uint256 amount);

    // ============ Errors ============
    error ZeroAddress();
    error ZeroAmount();
    error NotWhitelisted();
    error EmptyTrade();
    error InsufficientBalance();
    error RecallExceedsDeployed();
    error AlreadyWhitelisted();
    error NotInWhitelist();

    // ============ Constructor ============
    /**
     * @notice Initialize the engine
     * @param _vault Address of AmendVaultV2
     * @param _admin Initial admin address
     */
    constructor(address _vault, address _admin) {
        if (_vault == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        VAULT = IAmendVaultV2(_vault);
        ASSET = IERC20(VAULT.asset());

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(REPORTER_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
    }

    // ============ Whitelist Management ============

    /**
     * @notice Add destination to whitelist
     * @param destination Address to whitelist
     */
    function addToWhitelist(address destination) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (destination == address(0)) revert ZeroAddress();
        if (_whitelist[destination]) revert AlreadyWhitelisted();

        _whitelist[destination] = true;
        emit WhitelistAdded(destination);
    }

    /**
     * @notice Remove destination from whitelist
     * @param destination Address to remove
     */
    function removeFromWhitelist(address destination) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!_whitelist[destination]) revert NotInWhitelist();

        _whitelist[destination] = false;
        emit WhitelistRemoved(destination);
    }

    /**
     * @notice Check if destination is whitelisted
     * @param destination Address to check
     * @return True if whitelisted
     */
    function isWhitelisted(address destination) external view returns (bool) {
        return _whitelist[destination];
    }

    // ============ Pause Control ============

    /**
     * @notice Emergency pause - only EMERGENCY_ROLE
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause - only DEFAULT_ADMIN_ROLE
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Check if engine is paused
     * @return True if paused
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    // ============ Fund Deployment ============

    /**
     * @notice Deploy funds from Vault to whitelisted destination
     * @param destination Target address (must be whitelisted)
     * @param amount Amount to deploy
     */
    function deployFunds(address destination, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (!_whitelist[destination]) revert NotWhitelisted();
        if (amount == 0) revert ZeroAmount();

        // Request funds from Vault
        VAULT.invest(amount);

        // Track deployment
        _deployed[destination] += amount;
        _totalDeployed += amount;

        // Transfer to destination
        ASSET.safeTransfer(destination, amount);

        emit FundsDeployed(destination, amount);
    }

    /**
     * @notice Recall funds from destination back to Engine
     * @param destination Source address
     * @param amount Amount to recall
     */
    function recallFunds(address destination, uint256 amount)
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > _deployed[destination]) revert RecallExceedsDeployed();

        // Update accounting
        _deployed[destination] -= amount;
        _totalDeployed -= amount;

        // Pull funds from destination (destination must have approved Engine)
        ASSET.safeTransferFrom(destination, address(this), amount);

        emit FundsRecalled(destination, amount);
    }

    // ============ Settlement (ATOMIC) ============

    /**
     * @notice Atomic trade settlement - Approve then signal Vault to pull
     * @param principal Original capital being returned
     * @param profit Earned profit (0 if none)
     */
    function finalizeTrade(uint256 principal, uint256 profit)
        external
        onlyRole(REPORTER_ROLE)
        nonReentrant
        whenNotPaused
    {
        uint256 total = principal + profit;
        if (total == 0) revert EmptyTrade();
        if (ASSET.balanceOf(address(this)) < total) revert InsufficientBalance();

        // Approve Vault to pull
        ASSET.forceApprove(address(VAULT), total);

        // Signal Vault to pull (atomic settlement)
        VAULT.repay(principal, profit);

        emit TradeFinalized(principal, profit);
    }

    /**
     * @notice Report loss to Vault
     * @param loss Amount of capital lost
     */
    function reportLoss(uint256 loss)
        external
        onlyRole(REPORTER_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (loss == 0) revert ZeroAmount();

        // Report to Vault (no funds transferred)
        VAULT.reportLoss(loss);

        emit LossReported(loss);
    }

    // ============ Emergency Functions ============

    /**
     * @notice Emergency recall all funds from a destination
     * @dev Works even when paused
     * @param destination Address to recall from
     */
    function emergencyRecall(address destination)
        external
        onlyRole(EMERGENCY_ROLE)
        nonReentrant
    {
        uint256 deployed = _deployed[destination];
        if (deployed == 0) revert ZeroAmount();

        // Update accounting
        _deployed[destination] = 0;
        _totalDeployed -= deployed;

        // Pull all funds (destination must have approved Engine)
        uint256 balance = ASSET.balanceOf(destination);
        uint256 recallAmount = balance < deployed ? balance : deployed;

        if (recallAmount > 0) {
            ASSET.safeTransferFrom(destination, address(this), recallAmount);
        }

        emit EmergencyRecall(destination, recallAmount);
    }

    // ============ View Functions ============

    /**
     * @notice Get amount deployed to a destination
     * @param destination Address to query
     * @return Amount deployed
     */
    function getDeployedTo(address destination) external view returns (uint256) {
        return _deployed[destination];
    }

    /**
     * @notice Get total amount deployed across all destinations
     * @return Total deployed
     */
    function getTotalDeployed() external view returns (uint256) {
        return _totalDeployed;
    }

    /**
     * @notice Get vault address
     * @return Vault address
     */
    function vault() external view returns (address) {
        return address(VAULT);
    }

    /**
     * @notice Get asset address
     * @return Asset address
     */
    function asset() external view returns (address) {
        return address(ASSET);
    }
}
