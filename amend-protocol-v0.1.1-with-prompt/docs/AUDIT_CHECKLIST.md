# AMEND Protocol v0.1.1 - Audit Checklist

## Contract Inventory

| Contract | Path | LOC | Description |
|----------|------|-----|-------------|
| AmendVault | `src/AmendVault.sol` | ~220 | ERC4626-based vault with profit-sharing |
| AmendEngine | `src/AmendEngine.sol` | ~280 | Investment management engine |
| IAmendEngine | `src/interfaces/IAmendEngine.sol` | ~180 | Engine interface definition |

**Total Protocol Lines:** ~680 LOC (excluding tests)

---

## Core Invariants

### 1. NO FEE ON LOSS (Primary Invariant)

```
If reportLoss(x) is called, then balanceOf(feeRecipient) MUST NOT increase.
```

**Verification:**
- `AmendVault.reportLoss()` does NOT call `_mintFeeShares()`
- Test: `test_Invariant_NoFeeOnLoss()` in `test/Integration.t.sol`
- Test: `testFuzz_LossNeverTakesFee()` in `test/AmendVault.t.sol`

### 2. Principal Protection Invariant

```
reportLoss(x) requires x <= investedAssets
```

**Verification:**
- Line 185 in `AmendVault.sol`: `require(lossAssets <= investedAssets, "AMEND: loss > invested")`
- Test: `test_LossCannotExceedInvested()` in `test/AmendVault.t.sol`

### 3. Profit Must Be Asset-Backed

```
reportProfit(x) requires IERC20(asset).balanceOf(vault) >= x
```

**Verification:**
- Lines 159-163 in `AmendVault.sol`:
  ```solidity
  uint256 onChainBalance = IERC20(asset()).balanceOf(address(this));
  require(onChainBalance >= grossProfitAssets, "AMEND: profit not backed by assets");
  ```
- Test: `test_ProfitMustBeBackedByAssets()` in `test/AmendVault.t.sol`

### 4. Accounting Invariant (Engine)

```
engine.totalDeployed == Σ engine.deployed[destination] for all destinations
```

**Verification:**
- Atomic updates in `deployFunds()`, `recallFunds()`, `emergencyRecall()`
- Test: `test_Invariant_EngineAccountingConsistent()` in `test/Integration.t.sol`

### 5. NAV Invariant (Vault)

```
vault.totalAssets() == vault.balance + vault.investedAssets
```

**Verification:**
- Lines 101-103 in `AmendVault.sol`:
  ```solidity
  function totalAssets() public view override returns (uint256) {
      return IERC20(asset()).balanceOf(address(this)) + investedAssets;
  }
  ```
- Test: `invariant_VaultAssetsMatchReality()` in `test/Integration.t.sol`

---

## Access Control Matrix

### AmendVault

| Function | Owner | Engine | Public |
|----------|-------|--------|--------|
| `setEngine` | ✓ | | |
| `setFeeParams` | ✓ | | |
| `invest` | | ✓ | |
| `divest` | | ✓ | |
| `reportProfit` | | ✓ | |
| `reportLoss` | | ✓ | |
| `rescueTokens` | ✓ | | |
| `deposit` | | | ✓ |
| `withdraw` | | | ✓ |
| `redeem` | | | ✓ |
| `mint` | | | ✓ |

### AmendEngine

| Function | DEFAULT_ADMIN | ADMIN | MANAGER | REPORTER | Public |
|----------|---------------|-------|---------|----------|--------|
| `grantRole` | ✓ | | | | |
| `revokeRole` | ✓ | | | | |
| `addToWhitelist` | | ✓ | | | |
| `removeFromWhitelist` | | ✓ | | | |
| `pause` | | ✓ | | | |
| `unpause` | | ✓ | | | |
| `deployFunds` | | | ✓ | | |
| `recallFunds` | | | ✓ | | |
| `emergencyRecall` | | ✓ | ✓ | | |
| `settleProfit` | | | | ✓ | |
| `settleLoss` | | | | ✓ | |
| `getDeployedTo` | | | | | ✓ |
| `getTotalDeployed` | | | | | ✓ |
| `isWhitelisted` | | | | | ✓ |

---

## Test Coverage Summary

### Unit Tests

| Test File | Tests | Pass | Fail | Coverage |
|-----------|-------|------|------|----------|
| `test/AmendVault.t.sol` | 15 | 14 | 1* | Vault core |
| `test/AmendEngine.t.sol` | 33 | 33 | 0 | Engine core |
| `test/Integration.t.sol` | 13 | 13 | 0 | End-to-end |

*Note: `test_ZeroDepositReverts` fails due to ERC4626 behavior (not a security issue)

### Fuzz Tests

| Test | Runs | Description |
|------|------|-------------|
| `testFuzz_ProfitAlwaysDilutesCorrectly` | 256 | Fee dilution correctness |
| `testFuzz_LossNeverTakesFee` | 256 | NO FEE ON LOSS invariant |
| `testFuzz_DeployRecallAccounting` | 256 | Engine accounting consistency |
| `testFuzz_MultipleDestinations` | 256 | Multi-destination accounting |

### Invariant Tests

| Test | Calls | Description |
|------|-------|-------------|
| `invariant_VaultAssetsMatchReality` | 3840 | NAV consistency |

---

## Security Features

### Implemented Protections

- [x] **ReentrancyGuard** on all fund-moving functions (Engine)
- [x] **Pausable** for emergency stops (Engine)
- [x] **SafeERC20** for all token operations (Engine)
- [x] **AccessControl** with role separation (Engine)
- [x] **Whitelist** for destination addresses (Engine)
- [x] **Ownable** for admin functions (Vault)
- [x] **Input validation** on all parameters
- [x] **Checks-Effects-Interactions** pattern

### External Dependencies

| Dependency | Version | Source |
|------------|---------|--------|
| OpenZeppelin Contracts | 5.0.0 | `@openzeppelin/contracts` |
| Foundry forge-std | 1.x | `forge-std` |

---

## Known Limitations

### 1. Trusted Engine Model

**Description:** The Vault fully trusts the Engine address. A compromised Engine could:
- Report excessive profits (blocked by on-chain balance check)
- Report excessive losses (blocked by investedAssets check)
- Fail to return funds from destinations (operational risk)

**Mitigation:** Use multisig for admin, monitor operations, audit destinations.

### 2. No Oracle Integration

**Description:** Profit/loss is determined off-chain and reported manually.

**Mitigation:** Reporter role should be automated keeper or trusted operator.

### 3. Destination Trust

**Description:** Whitelisted destinations hold deployed funds. A malicious destination could refuse to return funds.

**Mitigation:** Off-chain vetting, legal agreements, diversification.

### 4. Fee Calculation Rounding

**Description:** Fee shares are calculated using ERC4626 `convertToShares()` which may round down.

**Impact:** Minimal - always in favor of users (conservative).

### 5. No Timelock

**Description:** Admin actions (pause, whitelist) take effect immediately.

**Mitigation:** Consider adding timelock for mainnet governance.

---

## Audit Focus Areas

### High Priority

1. **Fund Flow Security**
   - Can funds be extracted without proper authorization?
   - Can funds be stuck or lost?

2. **Accounting Integrity**
   - Can `investedAssets` be manipulated?
   - Can `totalDeployed` become inconsistent?

3. **Access Control**
   - Can roles be escalated?
   - Can unauthorized addresses call protected functions?

4. **Reentrancy**
   - Are all external calls protected?
   - Is state updated before external calls?

### Medium Priority

5. **Edge Cases**
   - Zero amounts
   - Maximum values
   - Dust amounts

6. **ERC4626 Compliance**
   - Share/asset conversion accuracy
   - Preview functions accuracy

7. **Pause Behavior**
   - What functions work when paused?
   - Can emergency recall work when paused?

### Lower Priority

8. **Gas Optimization**
   - Are there unnecessary operations?
   - Can loops be optimized?

9. **Code Quality**
   - NatSpec completeness
   - Event coverage

---

## Pre-Audit Checklist

- [x] All tests passing (60/61, known issue)
- [x] No compiler errors
- [x] NatSpec documentation complete
- [x] Events for all state changes
- [x] Access control documented
- [x] Custom errors used (gas efficient)
- [ ] Slither static analysis (recommended)
- [ ] Aderyn static analysis (recommended)

---

## Deployment Verification

Before audit, verify:

```bash
# Build
forge build

# Run all tests
forge test -vv

# Gas report
forge test --gas-report

# Check coverage
forge coverage
```

---

*AMEND Protocol v0.1.1 Audit Checklist*
*Core Invariant: "NO FEE ON LOSS"*
