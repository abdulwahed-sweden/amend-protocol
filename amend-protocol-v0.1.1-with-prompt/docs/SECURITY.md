# AMEND Protocol - Security Documentation

## Trust Model

### Trust Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                      VAULT OWNER                             │
│  Can: setEngine, setFeeParams, transferOwnership             │
│  Trust Level: HIGHEST                                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        ENGINE                                │
│  Can: invest, divest, reportProfit, reportLoss               │
│  Trust Level: HIGH (sole trusted address for fund movement)  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ENGINE ADMIN                              │
│  Can: whitelist, pause/unpause, grant/revoke roles           │
│  Trust Level: HIGH                                           │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────────┐
          ▼                                       ▼
┌─────────────────────┐               ┌─────────────────────┐
│   ENGINE MANAGER    │               │   ENGINE REPORTER   │
│  Can: deploy/recall │               │  Can: settle P&L    │
│  Trust: MEDIUM      │               │  Trust: MEDIUM      │
└─────────────────────┘               └─────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              WHITELISTED DESTINATIONS                        │
│  Can: Hold deployed funds, generate yield/loss               │
│  Trust Level: LOW (vetted but external)                      │
└─────────────────────────────────────────────────────────────┘
```

### Trust Boundaries

| Boundary | Protection |
|----------|-----------|
| User → Vault | ERC4626 standard, SafeERC20 |
| Vault → Engine | `onlyEngine` modifier |
| Engine → Destination | Whitelist enforcement |
| Reporter → Vault | Profit must be backed by assets |
| Reporter → Vault | Loss cannot exceed investedAssets |

## Security Features

### 1. Access Control (OpenZeppelin AccessControl)

```solidity
ADMIN_ROLE    → whitelist, pause, role management
MANAGER_ROLE  → deployFunds, recallFunds, emergencyRecall
REPORTER_ROLE → settleProfit, settleLoss
```

**Principle of Least Privilege:** Each role can only perform its specific functions.

### 2. Reentrancy Protection

All fund-moving functions use `ReentrancyGuard`:
- `deployFunds()`
- `recallFunds()`
- `emergencyRecall()`
- `settleProfit()`
- `settleLoss()`

### 3. Pausable

Emergency stop mechanism:
- `pause()` - Halts all fund operations
- `unpause()` - Resumes operations
- `emergencyRecall()` - Works even when paused

### 4. Safe Token Operations

All ERC20 interactions use OpenZeppelin's `SafeERC20`:
- `safeTransfer()`
- `safeTransferFrom()`
- `safeIncreaseAllowance()`

### 5. Input Validation

- Zero address checks on construction
- Zero amount checks on all operations
- Whitelist verification before deployment
- Balance/deployed checks before recalls

### 6. Checks-Effects-Interactions Pattern

All state-changing functions follow CEI:
1. **Checks**: Validate inputs and permissions
2. **Effects**: Update state variables
3. **Interactions**: Make external calls

Example from `deployFunds()`:
```solidity
function deployFunds(address destination, uint256 amount) external {
    // CHECKS
    if (amount == 0) revert ZeroAmount();
    if (!_whitelist[destination]) revert NotWhitelisted(destination);

    // EFFECTS
    _deployed[destination] += amount;
    _totalDeployed += amount;

    // INTERACTIONS
    IAmendVault(vault).invest(amount);
    IERC20(asset).safeTransfer(destination, amount);
}
```

## Attack Vector Analysis

### 1. Unauthorized Fund Movement

**Vector:** Attacker tries to move funds without proper role

**Mitigations:**
- AccessControl with separate roles
- `onlyEngine` modifier on Vault
- Whitelist enforcement on Engine

**Residual Risk:** LOW - Multiple layers of protection

### 2. Reentrancy

**Vector:** Malicious destination contract re-enters during transfer

**Mitigations:**
- ReentrancyGuard on all fund functions
- CEI pattern
- State updates before external calls

**Residual Risk:** LOW - Standard protections in place

### 3. Phantom Profit Reporting

**Vector:** Reporter claims profit without backing assets

**Mitigations:**
- Engine checks: `balance >= profitAmount`
- Vault checks: `onChainBalance >= grossProfitAssets`
- Profit must be transferred before reporting

**Residual Risk:** LOW - Double validation

### 4. Excessive Loss Reporting

**Vector:** Reporter claims more loss than invested

**Mitigations:**
- Vault enforces: `lossAssets <= investedAssets`

**Residual Risk:** LOW - Hard constraint

### 5. Destination Rug Pull

**Vector:** Whitelisted destination steals funds

**Mitigations:**
- Whitelist vetting process
- Emergency recall capability
- Per-destination accounting for tracking
- Off-chain monitoring

**Residual Risk:** MEDIUM - Depends on destination trustworthiness

### 6. Admin Key Compromise

**Vector:** Admin private key stolen

**Mitigations:**
- Use multisig for admin role
- Timelock on critical operations (recommended)
- Separate roles limit damage scope

**Residual Risk:** MEDIUM - Requires operational security

### 7. Accounting Manipulation

**Vector:** Exploit to corrupt accounting state

**Mitigations:**
- Atomic updates to `deployed[]` and `totalDeployed`
- Invariant: `totalDeployed == sum(deployed[])`
- No external calls between state updates

**Residual Risk:** LOW - Atomic operations

### 8. Griefing via Pause

**Vector:** Malicious admin pauses indefinitely

**Mitigations:**
- Multisig for admin role
- Emergency recall still works
- Vault operations (deposit/withdraw) unaffected

**Residual Risk:** LOW - Limited impact

## Invariants

### System Invariants

These must ALWAYS be true:

1. **Accounting Invariant**
   ```
   engine.totalDeployed == Σ engine.deployed[destination]
   ```

2. **NAV Invariant**
   ```
   vault.totalAssets == vault.balance + vault.investedAssets
   ```

3. **No Creation Invariant**
   ```
   Total USDC in system cannot increase without external deposit or profit
   ```

4. **Core Protocol Invariant**
   ```
   Fee is charged ONLY on profit, NEVER on loss
   ```

### Checked by Tests

- `test_Invariant_EngineAccountingConsistent`
- `test_Invariant_EngineCannotCreateMoney`
- `test_Invariant_NoFeeOnLoss`
- `invariant_VaultAssetsMatchReality`

## Audit Preparation

### Pre-Audit Checklist

- [ ] All tests passing
- [ ] No compiler warnings (except notes)
- [ ] NatSpec complete on all public functions
- [ ] Events emitted for all state changes
- [ ] Access control documented
- [ ] Slither/Aderyn static analysis run
- [ ] Gas optimization reviewed

### Known Issues / Accepted Risks

1. **Destination Trust**: Protocol relies on off-chain vetting of destinations
2. **Oracle-Free**: No on-chain price oracles; profit/loss determined off-chain
3. **Admin Centralization**: Admin has significant power; mitigate with multisig

### Recommended Audit Focus Areas

1. **Fund Flow**: Verify no funds can be extracted without proper authorization
2. **Accounting**: Verify deployed tracking cannot be manipulated
3. **Reentrancy**: Verify all external calls are protected
4. **Access Control**: Verify role separation is enforced
5. **Edge Cases**: Zero amounts, max values, dust amounts

## Incident Response

### Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| P0 | Active exploit, funds at risk | Immediate |
| P1 | Vulnerability found, not exploited | < 1 hour |
| P2 | Security weakness, no immediate risk | < 24 hours |
| P3 | Best practice improvement | < 1 week |

### Response Procedures

**P0 - Active Exploit:**
1. Pause Engine immediately
2. Emergency recall from all destinations
3. Notify users
4. Analyze attack vector
5. Prepare fix

**P1 - Vulnerability Found:**
1. Assess exploitability
2. Pause if necessary
3. Prepare and test fix
4. Deploy fix
5. Resume operations

### Contact

For security disclosures, contact: [security@amendprotocol.xyz]

## Dependency Security

### OpenZeppelin Contracts

Version: 5.0.0

Audited contracts used:
- `AccessControl.sol`
- `ReentrancyGuard.sol`
- `Pausable.sol`
- `SafeERC20.sol`
- `ERC4626.sol`
- `ERC20.sol`
- `Ownable.sol`

### Upgrade Path

If vulnerabilities are found in dependencies:
1. Review OpenZeppelin security advisories
2. Test new version compatibility
3. Redeploy contracts (not upgradeable)
4. Migrate users

---

*AMEND Protocol Security Documentation v0.1.1*
*Last Updated: [Deployment Date]*
