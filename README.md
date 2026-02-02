# AMEND Protocol

**Ethical Fee Architecture for ERC4626 Vaults**

> **Version:** v0.1.1
> **Status:** Production Ready (Testnet)
> **Audit:** Pending

---

## The Problem

Decentralized finance has introduced powerful primitives for capital coordination, but fee structures in yield-generating protocols often exhibit a fundamental asymmetry: protocols capture value regardless of performance outcomes, while users bear the full weight of downside risk.

This creates a misalignment of incentives:

- **Asymmetric risk distribution** — Protocol operators profit in all market conditions; depositors absorb losses alone.
- **Performance-agnostic fees** — Management fees accrue on assets under management, not on value created.
- **Opaque fee logic** — Fee extraction mechanics are often buried in complex accounting, making it difficult for users to verify fairness.
- **"Code is Law" as justification** — Technical immutability is used to normalize extractive structures, rather than to enforce ethical constraints.

These patterns are not malicious by design, but they reflect a gap in how fee mechanisms have been architected. AMEND Protocol addresses this gap.

---

## The AMEND Principle

AMEND introduces a mathematically enforced correction to fee architecture:

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                   NO FEE ON LOSS                        │
│                                                         │
│   Fees are extracted ONLY when realized profit > 0.    │
│   Losses NEVER trigger fee minting. Ever.              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

This is not a governance promise. It is a **structural invariant** enforced at the smart contract level:

- The `reportLoss()` function contains no fee logic.
- There is no conditional path that mints shares on loss.
- Fuzz testing with 256+ randomized scenarios confirms invariant integrity.
- The constraint is immutable once deployed.

---

## System Status

| Version | Status | Architecture | Description |
|---------|--------|--------------|-------------|
| **v0.1.1** | Production Ready | Explicit Settlement | Stable release enforcing core invariant. Engine pushes funds via `divest()` + `reportProfit()`. |
| **v0.2.0** | Beta / Under Review | Atomic Settlement | Vault pulls funds via `repay()`. Eliminates intermediate accounting states. |

**Important:**
- v0.2.0 does **not** replace v0.1.1.
- Both versions exist in parallel within this repository.
- v0.1.1 remains the production reference for audit and deployment.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         AMEND Protocol                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────┐         ┌─────────────┐         ┌──────────┐ │
│   │    User     │ deposit │  AmendVault │ invest  │  Amend   │ │
│   │             │────────►│  (ERC4626)  │────────►│  Engine  │ │
│   │             │◄────────│             │◄────────│          │ │
│   └─────────────┘ withdraw└─────────────┘  repay  └────┬─────┘ │
│                         │                              │       │
│                         │ Invariant Enforcement        │       │
│                         │ • NO FEE ON LOSS             │       │
│                         │ • Share dilution model       │       │
│                         │ • Principal protection       │       │
│                                                        ▼       │
│                                               ┌──────────────┐ │
│                                               │ Whitelisted  │ │
│                                               │ Destinations │ │
│                                               └──────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Component Responsibilities:**

| Component | Role |
|-----------|------|
| **AmendVault** | Manages deposits, withdrawals, share accounting, and invariant enforcement. ERC4626-compliant. |
| **AmendEngine** | Executes strategy operations: fund deployment, recall, and P&L reporting. Role-based access control. |
| **Destinations** | External contracts receiving deployed capital. Must be whitelisted and vetted off-chain. |

**Role Separation:**

| Role | Capability |
|------|------------|
| Vault Owner | Set engine, configure fees, rescue tokens |
| Engine Admin | Manage whitelist, pause/unpause |
| Engine Manager | Deploy and recall funds |
| Engine Reporter | Report profit and loss |

---

## Fee Mechanism

AMEND uses a **dilution-based fee model**:

- Fees are collected by minting new vault shares to the fee recipient.
- No assets are extracted from the vault.
- Total Value Locked (TVL) remains intact.
- Existing shareholders experience proportional dilution only when profit is realized.

**Fee Calculation:**
```
feeShares = convertToShares(profit * feeBps / 10000)
```

Shares are minted **only** when `profit > 0`.

---

## The Invariant

The core invariant is enforced in `reportLoss()`:

```solidity
function reportLoss(uint256 lossAssets) external onlyEngine nonReentrant {
    require(lossAssets > 0, "AMEND: zero loss");
    require(lossAssets <= investedAssets, "AMEND: loss > invested");

    investedAssets -= lossAssets;

    // ════════════════════════════════════════════════════════════
    // NO FEE IS EVER MINTED HERE — BY DESIGN
    // This is the ethical foundation of AMEND Protocol.
    // ════════════════════════════════════════════════════════════

    emit LossReported(lossAssets);
}
```

**Verification:**
- No `_mint()` call exists in any loss path.
- `require` statements prevent invalid loss reporting.
- Fuzz tests confirm fee recipient balance never increases on loss.
- No governance mechanism can override this constraint.

---

## Technical Specifications

| Property | Value |
|----------|-------|
| Token Standard | ERC4626 |
| Underlying Asset | USDC (configurable) |
| Solidity Version | 0.8.20 |
| Target Network | Base (L2) |
| Dependencies | OpenZeppelin Contracts v5.0.0 |
| Test Coverage | 102/103 tests passing |

---

## Repository Structure

```
amend-protocol/
├── src/                    # v0.1.1 Production Contracts
│   ├── AmendVault.sol
│   ├── AmendEngine.sol
│   └── interfaces/
│       └── IAmendEngine.sol
├── src/v2/                 # v0.2.0 Beta Contracts
│   ├── AmendVaultV2.sol
│   ├── AmendEngineV2.sol
│   └── interfaces/
│       └── IAmendVaultV2.sol
├── test/                   # v0.1.1 Tests
├── test/v2/                # v0.2.0 Tests
├── script/                 # Deployment Scripts
├── docs/                   # Documentation
└── docs/v2/                # v0.2.0 Documentation
```

---

## Getting Started

```bash
# Clone repository
git clone https://github.com/abdulwahed-sweden/amend-protocol.git
cd amend-protocol

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test -vv
```

For deployment instructions, see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

---

## Roadmap

| Milestone | Status |
|-----------|--------|
| v0.1.1 Core Implementation | Complete |
| v0.2.0 Atomic Settlement | Under Review |
| Testnet Deployment (Base Sepolia) | Pending |
| External Security Audit | Pending |
| Mainnet Deployment (Base) | Planned |

---

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md)
- [Operator Manual](docs/OPERATOR_MANUAL.md)
- [Audit Checklist](docs/AUDIT_CHECKLIST.md)
- [Security Model](docs/SECURITY.md)
- [v0.2.0 Changelog](docs/v2/CHANGELOG.md)
- [v0.2.0 Migration Guide](docs/v2/MIGRATION.md)

---

## Author

**Abdulwahed Mansour**

---

## License

MIT
