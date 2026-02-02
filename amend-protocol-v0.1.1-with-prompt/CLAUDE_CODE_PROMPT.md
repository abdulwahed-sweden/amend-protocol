# AMEND Protocol - Engine Development Prompt
## For Claude Code / AI-Assisted Development

---

## 🎯 PROJECT CONTEXT

You are the **Lead Smart Contract Engineer** for **AMEND Protocol** — an Islamic-compliant DeFi vault that implements profit-sharing with a core invariant: **"NO FEE ON LOSS"**.

### What Already Exists (DO NOT MODIFY):
- `src/AmendVault.sol` — The sealed vault contract (ERC4626-based)
- `test/AmendVault.t.sol` — Comprehensive test suite (passing)
- `foundry.toml` — Project configuration

### Your Mission:
Build the **AmendEngine.sol** contract that will manage investments on behalf of the Vault.

---

## 🔒 HARD CONSTRAINTS (NON-NEGOTIABLE)

```
┌─────────────────────────────────────────────────────────────────┐
│  1. DO NOT modify AmendVault.sol — it is FROZEN                 │
│  2. All funds flow: Vault → Engine → Whitelisted Addresses ONLY │
│  3. Engine CANNOT mint shares or manipulate Vault internals     │
│  4. Every state change MUST emit an event                       │
│  5. Use OpenZeppelin contracts for access control               │
│  6. Follow Checks-Effects-Interactions pattern                  │
│  7. All public functions MUST have NatSpec documentation        │
│  8. Gas optimization is secondary to security                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 DEVELOPMENT PHASES

Execute these phases **sequentially**. Do not proceed to the next phase until the current phase is complete and verified.

---

### PHASE 1: Architecture Design
**Output:** `docs/ENGINE_ARCHITECTURE.md`

**Tasks:**
1. Read and analyze `src/AmendVault.sol` completely
2. Document the interface between Vault and Engine
3. Define the Engine's responsibilities:
   - Receiving funds from Vault via `invest()`
   - Managing whitelisted investment destinations
   - Calculating and reporting profit/loss
   - Returning funds via `divest()`
4. Create a state machine diagram for fund lifecycle
5. List all required roles (MANAGER, ADMIN, REPORTER)

**Deliverable Format:**
```markdown
# AmendEngine Architecture

## 1. Contract Interface
[Define all external/public functions]

## 2. State Variables
[List with types and purposes]

## 3. Access Control Matrix
| Function | ADMIN | MANAGER | REPORTER | PUBLIC |
|----------|-------|---------|----------|--------|

## 4. Fund Flow Diagram
[ASCII or description]

## 5. Security Considerations
[List potential attack vectors and mitigations]
```

**Verification:** Architecture document exists and covers all sections.

---

### PHASE 2: Interface Definition
**Output:** `src/interfaces/IAmendEngine.sol`

**Tasks:**
1. Define the Engine interface based on Phase 1 architecture
2. Include all events that will be emitted
3. Include custom errors (gas-efficient reverts)
4. Add complete NatSpec documentation

**Code Template:**
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAmendEngine
 * @notice Interface for AMEND Protocol investment engine
 * @dev Manages fund deployment from AmendVault to whitelisted destinations
 */
interface IAmendEngine {
    // ============ Events ============
    
    // ============ Errors ============
    
    // ============ View Functions ============
    
    // ============ State-Changing Functions ============
}
```

**Verification:** Interface compiles without errors.

---

### PHASE 3: Core Implementation
**Output:** `src/AmendEngine.sol`

**Tasks:**
1. Implement the interface from Phase 2
2. Use OpenZeppelin's `AccessControl` for role management
3. Implement whitelist management for investment destinations
4. Implement fund tracking (per-destination accounting)
5. Implement profit/loss calculation logic
6. Add emergency functions (pause, emergency withdraw)

**Required State Variables:**
```solidity
address public immutable vault;           // The AmendVault address
address public immutable asset;           // USDC address
mapping(address => bool) public whitelist; // Allowed destinations
mapping(address => uint256) public deployed; // Funds per destination
uint256 public totalDeployed;             // Total funds out
```

**Required Functions:**
```solidity
// Admin functions
function addToWhitelist(address destination) external;
function removeFromWhitelist(address destination) external;

// Manager functions  
function deployFunds(address destination, uint256 amount) external;
function recallFunds(address destination, uint256 amount) external;

// Reporter functions
function settleProfit(uint256 profitAmount) external;
function settleLoss(uint256 lossAmount) external;

// View functions
function getDeployedTo(address destination) external view returns (uint256);
function getTotalDeployed() external view returns (uint256);
function isWhitelisted(address destination) external view returns (bool);
```

**Security Checklist:**
- [ ] ReentrancyGuard on all fund movements
- [ ] Pausable for emergency stops
- [ ] Input validation on all parameters
- [ ] Safe ERC20 operations (SafeERC20)
- [ ] No external calls before state updates

**Verification:** Contract compiles without errors or warnings.

---

### PHASE 4: Test Suite
**Output:** `test/AmendEngine.t.sol`

**Tasks:**
1. Create comprehensive test suite mirroring Vault tests quality
2. Test all access control scenarios
3. Test whitelist management
4. Test fund deployment and recall
5. Test profit/loss settlement flows
6. Test integration with AmendVault
7. Add fuzz tests for numerical operations

**Required Test Scenarios:**
```solidity
// Access Control
function test_OnlyAdminCanWhitelist() public {}
function test_OnlyManagerCanDeployFunds() public {}
function test_OnlyReporterCanSettle() public {}

// Whitelist
function test_AddToWhitelist() public {}
function test_RemoveFromWhitelist() public {}
function test_CannotDeployToNonWhitelisted() public {}

// Fund Management
function test_DeployFunds_Success() public {}
function test_DeployFunds_InsufficientBalance() public {}
function test_RecallFunds_Success() public {}
function test_RecallFunds_ExceedsDeployed() public {}

// Settlement
function test_SettleProfit_UpdatesVault() public {}
function test_SettleLoss_UpdatesVault() public {}

// Integration
function test_FullCycle_VaultToEngineAndBack() public {}

// Fuzz
function testFuzz_DeployRecallAccounting(uint256 amount) public {}
```

**Verification:** All tests pass with `forge test -vv`.

---

### PHASE 5: Integration Testing
**Output:** `test/Integration.t.sol`

**Tasks:**
1. Test complete user journey: Deposit → Invest → Profit → Withdraw
2. Test complete user journey: Deposit → Invest → Loss → Withdraw
3. Test multi-user scenarios
4. Test edge cases (max values, zero values)
5. Verify invariants across the entire system

**Key Invariant Tests:**
```solidity
// System-wide invariants
function invariant_VaultAssetsMatchReality() public {}
function invariant_EngineCannotCreateMoney() public {}
function invariant_NoFeeOnLoss() public {}
```

**Verification:** All integration tests pass.

---

### PHASE 6: Documentation & Cleanup
**Output:** Updated `README.md`, `docs/` folder

**Tasks:**
1. Update README with Engine documentation
2. Create deployment guide
3. Create operator manual (how to manage the Engine)
4. Add inline comments explaining complex logic
5. Run `forge fmt` for code formatting
6. Run `slither` or `aderyn` for static analysis (if available)

**Deliverables:**
- `docs/DEPLOYMENT.md` — How to deploy the system
- `docs/OPERATOR_GUIDE.md` — How to operate the Engine
- `docs/SECURITY.md` — Security considerations and audit prep

**Verification:** Documentation is complete and accurate.

---

## 📊 PROGRESS TRACKING

After completing each phase, output a status report:

```
╔═══════════════════════════════════════════════════════════════╗
║  PHASE [N] COMPLETE                                           ║
╠═══════════════════════════════════════════════════════════════╣
║  Files Created:                                               ║
║  - [list files]                                               ║
║                                                               ║
║  Tests Status:                                                ║
║  - Passed: X                                                  ║
║  - Failed: 0                                                  ║
║                                                               ║
║  Security Checklist:                                          ║
║  - [x] Item 1                                                 ║
║  - [x] Item 2                                                 ║
║                                                               ║
║  Ready for Phase [N+1]: YES/NO                                ║
╚═══════════════════════════════════════════════════════════════╝
```

---

## 🔍 REFERENCE MATERIALS

### Existing Vault Interface (for Engine integration):
```solidity
// Functions Engine will call on Vault:
function invest(uint256 assets) external;      // Vault sends USDC to Engine
function divest(uint256 assets) external;      // Engine returns USDC to Vault
function reportProfit(uint256 profit) external; // Engine reports gains
function reportLoss(uint256 loss) external;     // Engine reports losses

// Engine must implement:
// - Approve Vault to pull funds via transferFrom
// - Track all deployed capital accurately
// - Never report profit without backing assets
// - Never report loss exceeding invested amount
```

### OpenZeppelin Imports to Use:
```solidity
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
```

---

## ⚠️ CRITICAL REMINDERS

1. **Trust Boundary:** The Engine is the ONLY address the Vault trusts. Any vulnerability here compromises the entire protocol.

2. **Accounting Accuracy:** `totalDeployed` must ALWAYS equal the sum of all `deployed[destination]` values.

3. **Vault Constraints:** Remember the Vault enforces:
   - `reportLoss(x)` requires `x <= investedAssets`
   - `reportProfit(x)` requires `onChainBalance >= x`

4. **No Magic Money:** The Engine cannot create assets. It can only move existing assets between Vault and whitelisted destinations.

5. **Auditability:** Every fund movement must be traceable via events.

---

## 🚀 BEGIN EXECUTION

Start with **PHASE 1**. Read the existing codebase thoroughly before writing any new code.

Command to begin:
```bash
cd /path/to/amend-protocol
cat src/AmendVault.sol
cat test/AmendVault.t.sol
```

Then create the architecture document and await confirmation before proceeding.

---

*This prompt was generated for AMEND Protocol v0.1.1*
*Core Invariant: "NO FEE ON LOSS" — تصحيح الظلم المالي*
