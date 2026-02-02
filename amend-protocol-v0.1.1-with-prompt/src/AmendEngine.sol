// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAmendEngine } from "./interfaces/IAmendEngine.sol";

/// @dev Interface for interacting with the AmendVault
interface IAmendVault {
    function invest(uint256 assets) external;
    function divest(uint256 assetsReturned) external;
    function reportProfit(uint256 grossProfitAssets) external;
    function reportLoss(uint256 lossAssets) external;
    function asset() external view returns (address);
}

/**
 * @title AmendEngine
 * @notice Investment engine for AMEND Protocol - manages fund deployment to whitelisted destinations
 * @dev This contract is the trusted intermediary between AmendVault and external investment destinations.
 *
 * Core Responsibilities:
 * 1. Manage whitelist of allowed investment destinations
 * 2. Deploy funds from Vault to destinations
 * 3. Recall funds from destinations back to Vault
 * 4. Report profit/loss to Vault for NAV adjustment
 *
 * Security Model:
 * - Only ADMIN can manage whitelist and pause/unpause
 * - Only MANAGER can deploy/recall funds
 * - Only REPORTER can settle profit/loss
 * - ReentrancyGuard on all fund-moving functions
 * - Pausable for emergency stops
 *
 * Key Invariants:
 * - totalDeployed == sum(deployed[destination])
 * - Funds can only go to whitelisted addresses
 * - Profit must be backed by actual assets
 */
contract AmendEngine is IAmendEngine, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Role Constants ============

    /// @notice Role for administrative functions (whitelist, pause)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Role for fund management (deploy, recall)
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Role for settlement (profit/loss reporting)
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    // ============ Immutable State ============

    /// @notice The AmendVault contract this engine serves
    address public immutable override vault;

    /// @notice The underlying asset (USDC)
    address public immutable override asset;

    // ============ Mutable State ============

    /// @notice Addresses allowed to receive deployed funds
    mapping(address => bool) private _whitelist;

    /// @notice Amount of assets deployed to each destination
    mapping(address => uint256) private _deployed;

    /// @notice Total amount of assets deployed across all destinations
    uint256 private _totalDeployed;

    // ============ Constructor ============

    /**
     * @notice Initialize the AmendEngine
     * @param vault_ The AmendVault address this engine will serve
     * @param admin_ The initial admin address (receives DEFAULT_ADMIN_ROLE)
     */
    constructor(address vault_, address admin_) {
        if (vault_ == address(0)) revert ZeroAddress();
        if (admin_ == address(0)) revert ZeroAddress();

        vault = vault_;
        asset = IAmendVault(vault_).asset();

        // Setup roles - admin gets all management roles initially
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ADMIN_ROLE, admin_);
        _grantRole(MANAGER_ROLE, admin_);
        _grantRole(REPORTER_ROLE, admin_);
    }

    // ============ Admin Functions ============

    /**
     * @inheritdoc IAmendEngine
     */
    function addToWhitelist(address destination) external override onlyRole(ADMIN_ROLE) {
        if (destination == address(0)) revert ZeroAddress();
        if (_whitelist[destination]) revert AlreadyWhitelisted(destination);

        _whitelist[destination] = true;

        emit WhitelistAdded(destination);
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function removeFromWhitelist(address destination) external override onlyRole(ADMIN_ROLE) {
        if (!_whitelist[destination]) revert NotWhitelisted(destination);

        uint256 deployedAmount = _deployed[destination];
        if (deployedAmount > 0) {
            revert CannotRemoveWithDeployedFunds(destination, deployedAmount);
        }

        _whitelist[destination] = false;

        emit WhitelistRemoved(destination);
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function pause() external override onlyRole(ADMIN_ROLE) {
        _pause();
        // Note: Pausable emits Paused(address account) event
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function unpause() external override onlyRole(ADMIN_ROLE) {
        _unpause();
        // Note: Pausable emits Unpaused(address account) event
    }

    // ============ Manager Functions ============

    /**
     * @inheritdoc IAmendEngine
     */
    function deployFunds(address destination, uint256 amount)
        external
        override
        onlyRole(MANAGER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Checks
        if (amount == 0) revert ZeroAmount();
        if (!_whitelist[destination]) revert NotWhitelisted(destination);

        // Effects - update accounting BEFORE external calls
        _deployed[destination] += amount;
        _totalDeployed += amount;

        // Interactions
        // 1. Pull funds from Vault to Engine
        IAmendVault(vault).invest(amount);

        // 2. Transfer funds from Engine to destination
        IERC20(asset).safeTransfer(destination, amount);

        emit FundsDeployed(destination, amount);
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function recallFunds(address destination, uint256 amount)
        external
        override
        onlyRole(MANAGER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Checks
        if (amount == 0) revert ZeroAmount();

        uint256 deployedAmount = _deployed[destination];
        if (amount > deployedAmount) {
            revert RecallExceedsDeployed(destination, amount, deployedAmount);
        }

        // Effects - update accounting BEFORE external calls
        _deployed[destination] -= amount;
        _totalDeployed -= amount;

        // Interactions
        // Pull funds from destination to Engine
        // Note: Destination must have approved Engine beforehand
        IERC20(asset).safeTransferFrom(destination, address(this), amount);

        // Approve Vault to pull funds from Engine
        IERC20(asset).safeIncreaseAllowance(vault, amount);

        // Return funds to Vault
        IAmendVault(vault).divest(amount);

        emit FundsRecalled(destination, amount);
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function emergencyRecall(address destination) external override nonReentrant {
        // Either ADMIN or MANAGER can emergency recall
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(MANAGER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, MANAGER_ROLE);
        }

        uint256 deployedAmount = _deployed[destination];
        if (deployedAmount == 0) revert ZeroAmount();

        // Effects
        _deployed[destination] = 0;
        _totalDeployed -= deployedAmount;

        // Interactions
        // Try to pull all deployed funds from destination
        IERC20(asset).safeTransferFrom(destination, address(this), deployedAmount);

        // Approve Vault to pull funds
        IERC20(asset).safeIncreaseAllowance(vault, deployedAmount);

        // Return to Vault
        IAmendVault(vault).divest(deployedAmount);

        emit EmergencyRecall(destination, deployedAmount);
    }

    // ============ Reporter Functions ============

    /**
     * @inheritdoc IAmendEngine
     */
    function settleProfit(uint256 profitAmount)
        external
        override
        onlyRole(REPORTER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Checks
        if (profitAmount == 0) revert NothingToSettle();

        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance < profitAmount) {
            revert ProfitNotBacked(profitAmount, balance);
        }

        // Interactions
        // 1. Transfer profit to Vault (must be in Vault before reportProfit)
        IERC20(asset).safeTransfer(vault, profitAmount);

        // 2. Report profit to Vault (triggers fee calculation)
        IAmendVault(vault).reportProfit(profitAmount);

        emit ProfitSettled(profitAmount);
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function settleLoss(uint256 lossAmount)
        external
        override
        onlyRole(REPORTER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Checks
        if (lossAmount == 0) revert NothingToSettle();

        // Note: We don't reduce _totalDeployed here because the loss
        // represents funds that are GONE (not deployed anymore).
        // The accounting adjustment was already made when the destination
        // returned fewer funds than deployed.

        // Interactions - report loss to Vault (NO FEE on loss)
        IAmendVault(vault).reportLoss(lossAmount);

        emit LossSettled(lossAmount);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAmendEngine
     */
    function getDeployedTo(address destination) external view override returns (uint256) {
        return _deployed[destination];
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function getTotalDeployed() external view override returns (uint256) {
        return _totalDeployed;
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function isWhitelisted(address destination) external view override returns (bool) {
        return _whitelist[destination];
    }

    /**
     * @inheritdoc IAmendEngine
     */
    function isPaused() external view override returns (bool) {
        return paused();
    }
}
