# AMEND Protocol v0.2.0 — Changelog

## Architecture Change: "Vault Pulls Always"

### Overview

v0.2.0 introduces atomic settlement, replacing the two-transaction settlement flow
with a single atomic operation where the Vault pulls funds from the Engine.

### Removed (from v0.1.1)

- `divest(uint256)` — replaced by `repay()`
- `reportProfit(uint256)` — merged into `repay()`
- `ADMIN_ROLE` and `MANAGER_ROLE` — replaced by `OPERATOR_ROLE`

### Added

**AmendVaultV2:**
- `repay(uint256 principal, uint256 profit)` — atomic settlement
- Vault pulls funds from Engine via `safeTransferFrom`
- Single entry point for returning capital and profit

**AmendEngineV2:**
- `finalizeTrade(uint256 principal, uint256 profit)` — initiates atomic settlement
- `OPERATOR_ROLE` — combines deploy and recall operations
- `REPORTER_ROLE` — settlement and loss reporting
- `EMERGENCY_ROLE` — separate pause authority from admin

### Security Improvements

1. **Single Settlement Path**
   - Reduces attack surface
   - No intermediate states between divest and reportProfit
   - Atomic accounting updates

2. **Strict Principal Validation**
   - `require(principal <= investedAssets)`
   - Prevents over-claiming

3. **CEI Pattern Enforced**
   - Checks-Effects-Interactions throughout
   - State updated before external calls

4. **Separated Pause Authority**
   - `EMERGENCY_ROLE` can pause
   - Only `DEFAULT_ADMIN_ROLE` can unpause
   - Prevents single point of failure

### ERC4626 Compliance

Full compatibility maintained:
- `deposit(uint256 assets, address receiver)` ✓
- `withdraw(uint256 assets, address receiver, address owner)` ✓
- `redeem(uint256 shares, address receiver, address owner)` ✓
- `convertToAssets(uint256 shares)` ✓
- `convertToShares(uint256 assets)` ✓
- `totalAssets()` ✓
- All preview functions ✓

### Invariant Preserved

**NO FEE ON LOSS** ✓

The core ethical invariant remains unchanged:
- Fees are ONLY charged on realized profit
- `reportLoss()` never mints fee shares
- Fuzz tested with 256+ random loss scenarios

### Migration Notes

v0.2.0 is a **parallel deployment**, not an upgrade to v0.1.1.
See [MIGRATION.md](./MIGRATION.md) for migration guidance.

---

*AMEND Protocol v0.2.0*
*Author: Abdulwahed Mansour*
