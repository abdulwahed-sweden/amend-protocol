# AmendEngine Architecture

## Overview

The AmendEngine contract is the trusted intermediary between the AmendVault and external investment destinations. It manages the deployment of capital, tracks accounting per destination, and reports profit/loss back to the Vault.

**Core Principle:** The Engine cannot create money. It can only move existing assets between the Vault and whitelisted destinations.

---

## 1. Contract Interface

### Admin Functions (ADMIN role)
```solidity
/// @notice Add an address to the whitelist of allowed investment destinations
function addToWhitelist(address destination) external;

/// @notice Remove an address from the whitelist
function removeFromWhitelist(address destination) external;

/// @notice Emergency pause all fund movements
function pause() external;

/// @notice Resume operations after pause
function unpause() external;
```

### Manager Functions (MANAGER role)
```solidity
/// @notice Deploy funds from Engine to a whitelisted destination
/// @dev Pulls funds from Vault via invest(), then transfers to destination
function deployFunds(address destination, uint256 amount) external;

/// @notice Recall funds from a destination back to Engine
/// @dev Destination must transfer funds back, then Engine calls divest() on Vault
function recallFunds(address destination, uint256 amount) external;

/// @notice Emergency recall all funds from a destination
function emergencyRecall(address destination) external;
```

### Reporter Functions (REPORTER role)
```solidity
/// @notice Report profit to the Vault after funds are returned
/// @dev Transfers profit to Vault, then calls reportProfit()
function settleProfit(uint256 profitAmount) external;

/// @notice Report loss to the Vault
/// @dev Calls reportLoss() on Vault to adjust NAV
function settleLoss(uint256 lossAmount) external;
```

### View Functions (PUBLIC)
```solidity
/// @notice Get amount deployed to a specific destination
function getDeployedTo(address destination) external view returns (uint256);

/// @notice Get total amount deployed across all destinations
function getTotalDeployed() external view returns (uint256);

/// @notice Check if an address is whitelisted
function isWhitelisted(address destination) external view returns (bool);

/// @notice Get the underlying asset address (USDC)
function asset() external view returns (address);

/// @notice Get the linked Vault address
function vault() external view returns (address);
```

---

## 2. State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `vault` | `address immutable` | The AmendVault contract address |
| `asset` | `address immutable` | The underlying asset (USDC) address |
| `whitelist` | `mapping(address => bool)` | Addresses allowed to receive deployed funds |
| `deployed` | `mapping(address => uint256)` | Amount of assets deployed to each destination |
| `totalDeployed` | `uint256` | Sum of all deployed assets (invariant: equals sum of `deployed[]`) |
| `paused` | `bool` | Emergency pause state |

### Role Constants
```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
```

---

## 3. Access Control Matrix

| Function | DEFAULT_ADMIN | ADMIN | MANAGER | REPORTER | PUBLIC |
|----------|---------------|-------|---------|----------|--------|
| `addToWhitelist` | | X | | | |
| `removeFromWhitelist` | | X | | | |
| `pause` | | X | | | |
| `unpause` | | X | | | |
| `deployFunds` | | | X | | |
| `recallFunds` | | | X | | |
| `emergencyRecall` | | X | X | | |
| `settleProfit` | | | | X | |
| `settleLoss` | | | | X | |
| `getDeployedTo` | | | | | X |
| `getTotalDeployed` | | | | | X |
| `isWhitelisted` | | | | | X |
| `asset` | | | | | X |
| `vault` | | | | | X |
| `grantRole` | X | | | | |
| `revokeRole` | X | | | | |

---

## 4. Fund Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FUND FLOW LIFECYCLE                                │
└─────────────────────────────────────────────────────────────────────────────┘

  USERS                    VAULT                    ENGINE               DESTINATIONS
    │                        │                        │                      │
    │  deposit(assets)       │                        │                      │
    ├───────────────────────►│                        │                      │
    │                        │                        │                      │
    │                        │   invest(amount)       │                      │
    │                        │◄───────────────────────┤ [Manager calls]      │
    │                        │                        │                      │
    │                        │   USDC transfer        │                      │
    │                        ├───────────────────────►│                      │
    │                        │                        │                      │
    │                        │                        │  deployFunds()       │
    │                        │                        ├─────────────────────►│
    │                        │                        │   USDC transfer      │
    │                        │                        │                      │
    │                        │                        │                      │
    │                        │                        │   [Destination       │
    │                        │                        │    generates         │
    │                        │                        │    yield/loss]       │
    │                        │                        │                      │
    │                        │                        │  recallFunds()       │
    │                        │                        │◄─────────────────────┤
    │                        │                        │   USDC transfer      │
    │                        │                        │                      │
    │                        │  divest(assets)        │                      │
    │                        │◄───────────────────────┤ [Returns funds]      │
    │                        │   USDC transferFrom    │                      │
    │                        │                        │                      │
    │                        │  reportProfit(amount)  │                      │
    │                        │◄───────────────────────┤ [If profitable]      │
    │                        │   [Fee taken here]     │                      │
    │                        │                        │                      │
    │                        │  reportLoss(amount)    │                      │
    │                        │◄───────────────────────┤ [If loss]            │
    │                        │   [NO FEE]             │                      │
    │                        │                        │                      │
    │  withdraw(assets)      │                        │                      │
    │◄───────────────────────┤                        │                      │
    │                        │                        │                      │
```

### State Machine: Fund States

```
┌──────────┐     invest()      ┌───────────┐    deployFunds()   ┌────────────┐
│  VAULT   │ ─────────────────►│  ENGINE   │ ─────────────────► │DESTINATION │
│(on-chain)│                   │(in-transit)│                    │ (deployed) │
└──────────┘                   └───────────┘                    └────────────┘
     ▲                              │  ▲                              │
     │                              │  │                              │
     │      divest()                │  │      recallFunds()           │
     └──────────────────────────────┘  └──────────────────────────────┘
```

---

## 5. Security Considerations

### Attack Vectors and Mitigations

| Attack Vector | Risk | Mitigation |
|--------------|------|------------|
| **Unauthorized fund movement** | HIGH | AccessControl with separate roles (ADMIN, MANAGER, REPORTER) |
| **Reentrancy** | HIGH | ReentrancyGuard on all fund-moving functions |
| **Non-whitelisted destination** | HIGH | Whitelist check before any deployment |
| **Accounting manipulation** | CRITICAL | Atomic updates to `deployed[]` and `totalDeployed` |
| **Griefing via pause** | MEDIUM | Only ADMIN can pause; emergency recall still works |
| **Phantom profit reporting** | CRITICAL | Vault enforces `onChainBalance >= profit`; Engine must transfer first |
| **Loss exceeding invested** | HIGH | Vault enforces `loss <= investedAssets` |
| **Destination rug** | MEDIUM | Whitelist + monitoring; emergency recall capability |
| **Flash loan attack** | LOW | No flash-mintable shares; NAV based on tracked amounts |

### Invariants

1. **Accounting Invariant:**
   ```
   totalDeployed == sum(deployed[destination] for all destinations)
   ```

2. **Balance Invariant:**
   ```
   Engine USDC balance + totalDeployed == Total assets controlled by Engine
   ```

3. **Trust Boundary:**
   - Engine is the ONLY address Vault trusts
   - Engine must NEVER report profit without backing assets
   - Engine must NEVER report loss exceeding invested amount

4. **Whitelist Invariant:**
   - Funds can ONLY flow to whitelisted addresses
   - Removal from whitelist does NOT affect already-deployed funds

### Checks-Effects-Interactions Pattern

Every state-changing function MUST follow:
1. **Checks:** Validate all inputs, permissions, and preconditions
2. **Effects:** Update state variables
3. **Interactions:** Make external calls (transfer, Vault calls)

---

## 6. Events

```solidity
// Whitelist Management
event WhitelistAdded(address indexed destination);
event WhitelistRemoved(address indexed destination);

// Fund Movement
event FundsDeployed(address indexed destination, uint256 amount);
event FundsRecalled(address indexed destination, uint256 amount);
event EmergencyRecall(address indexed destination, uint256 amount);

// Settlement
event ProfitSettled(uint256 profitAmount);
event LossSettled(uint256 lossAmount);

// Emergency
event Paused(address indexed by);
event Unpaused(address indexed by);
```

---

## 7. Custom Errors

```solidity
// Whitelist errors
error NotWhitelisted(address destination);
error AlreadyWhitelisted(address destination);
error CannotRemoveWithDeployedFunds(address destination, uint256 deployed);

// Fund errors
error ZeroAmount();
error InsufficientBalance(uint256 requested, uint256 available);
error DeploymentExceedsDeployed(address destination, uint256 requested, uint256 deployed);

// State errors
error ContractPaused();
error ZeroAddress();

// Settlement errors
error NothingToSettle();
error ProfitNotBacked(uint256 profit, uint256 balance);
```

---

## 8. Integration with AmendVault

### Functions Engine Calls on Vault

| Function | When Called | Purpose |
|----------|-------------|---------|
| `invest(amount)` | Before deploying funds | Pull USDC from Vault to Engine |
| `divest(amount)` | After recalling funds | Return USDC from Engine to Vault |
| `reportProfit(profit)` | After profit realized | Trigger fee calculation (dilution) |
| `reportLoss(loss)` | After loss realized | Update NAV (NO FEE) |

### Trust Requirements

1. **Engine → Vault:** Engine must approve Vault to `transferFrom` for `divest()`
2. **Destination → Engine:** Destinations must transfer back to Engine for `recallFunds()`
3. **Engine → Destination:** Engine transfers to whitelisted destinations only

### Workflow: Profit Realization

```solidity
// 1. Recall funds from destination (includes profit)
recallFunds(destination, principal + profit);

// 2. Transfer profit to Vault
IERC20(asset).transfer(vault, profit);

// 3. Return principal to Vault
IERC20(asset).approve(vault, principal);
vault.divest(principal);

// 4. Report profit (Vault takes fee here)
vault.reportProfit(profit);
```

### Workflow: Loss Realization

```solidity
// 1. Recall remaining funds from destination
recallFunds(destination, principal - loss);

// 2. Return remaining to Vault
IERC20(asset).approve(vault, principal - loss);
vault.divest(principal - loss);

// 3. Report loss (NO FEE)
vault.reportLoss(loss);
```

---

## 9. Constructor Parameters

```solidity
constructor(
    address vault_,           // AmendVault address
    address admin_           // Initial admin (gets DEFAULT_ADMIN_ROLE)
)
```

The `asset` is derived from `vault.asset()` to ensure consistency.

---

## 10. Deployment Checklist

1. [ ] Deploy Engine with Vault address
2. [ ] Grant ADMIN_ROLE to operational multisig
3. [ ] Grant MANAGER_ROLE to investment managers
4. [ ] Grant REPORTER_ROLE to settlement system/keeper
5. [ ] Call `vault.setEngine(engineAddress)` from Vault owner
6. [ ] Add initial destinations to whitelist
7. [ ] Verify roles and permissions

---

*Architecture Document - AMEND Protocol v0.1.1*
*Core Invariant: "NO FEE ON LOSS"*
