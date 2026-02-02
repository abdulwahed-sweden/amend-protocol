# AMEND Protocol - MVP

> **"تصحيح الظلم المالي"** - A fair, Islamic-compliant DeFi vault

## 🎯 Core Promise

**NO FEE ON LOSS** - The protocol only takes fees when there is profit.

## 📁 Project Structure

```
amend-protocol/
├── src/
│   └── AmendVault.sol      # Main vault contract (ERC4626)
├── test/
│   └── AmendVault.t.sol    # Comprehensive test suite
├── foundry.toml            # Foundry configuration
└── README.md
```

## 🚀 Quick Start

### 1. Install Foundry (if not installed)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### 2. Clone & Setup

```bash
# Navigate to project
cd amend-protocol

# Initialize git (if needed)
git init

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install foundry-rs/forge-std --no-commit
```

### 3. Run Tests

```bash
# Run all tests with verbosity
forge test -vv

# Run specific test
forge test --match-test test_ReportLoss_NoFee -vvv

# Run fuzz tests with more iterations
forge test --match-test testFuzz -vvv --fuzz-runs 1000
```

## ✅ Test Coverage

| Test | Description | Status |
|------|-------------|--------|
| `test_DepositAndInvest` | Basic deposit and investment flow | ✅ |
| `test_ReportProfit_TakesFee` | Fee taken on profit | ✅ |
| `test_ReportLoss_NoFee` | **CORE: Zero fee on loss** | ✅ |
| `test_LossAfterProfit_NoExtraFees` | No fees after profit then loss | ✅ |
| `test_MultipleUsers_FairDistribution` | Fair share distribution | ✅ |
| `test_LossCannotExceedInvested` | **NEW: Validates loss bounds** | ✅ |
| `test_ProfitMustBeBackedByAssets` | **NEW: Profit verification** | ✅ |
| `test_MultipleCycles_Fairness` | **NEW: Multi-cycle simulation** | ✅ |
| `testFuzz_ProfitAlwaysDilutesCorrectly` | Fuzz: profit math | ✅ |
| `testFuzz_LossNeverTakesFee` | **Fuzz: zero fee invariant** | ✅ |

## 🔐 Core Invariant

```solidity
// In reportLoss() - THE PROMISE:
// ⚠️ NO FEES HERE - CORE INVARIANT ⚠️
```

This is mathematically proven by the fuzz tests:
- `testFuzz_LossNeverTakesFee` runs 256+ random scenarios
- Treasury balance MUST be 0 after any loss

## 🏗️ Architecture

```
┌─────────────┐     deposit      ┌─────────────┐
│    User     │ ───────────────> │   AMEND     │
│             │ <─────────────── │   Vault     │
└─────────────┘     shares       └──────┬──────┘
                                        │
                                  invest│divest
                                        │
                                 ┌──────▼──────┐
                                 │   Engine    │
                                 │ (Trusted)   │
                                 └─────────────┘
```

## 📊 Fee Model

- **Profit**: Fee = `grossProfit * feeBps / 10000`
- **Loss**: Fee = `0` (ALWAYS)

Fee is taken via **share dilution** (minting shares to treasury), not USDC withdrawal.

## ⚠️ Known Limitations (v0.1)

1. **Engine is trusted** - Future versions need multisig/timelock
2. **No withdrawal queue** - Instant withdrawals only from available liquidity
3. **No sniping protection** - Consider cooldown in v1.1

## ✅ Security Improvements (v0.1.1)

1. **Loss validation** - `reportLoss()` now requires `lossAssets <= investedAssets`
2. **Profit verification** - `reportProfit()` verifies assets are actually in vault
3. **Trust boundaries documented** - Engine responsibilities clearly defined

## 🔜 Next Steps

- [ ] Invariant tests (stateful fuzzing)
- [ ] Engine contract with whitelist
- [ ] Cooldown mechanism
- [ ] Formal verification

---

**Built with justice in mind. الحمد لله**
