# AMEND Protocol

**Version:** v0.1.1 | **Status:** Production Ready | **Audit:** Pending

A fair, Islamic-compliant DeFi vault protocol implementing profit-sharing with transparent fee mechanics.

## Core Invariant

**NO FEE ON LOSS** - The protocol only charges fees when investments generate profit. If a loss occurs, depositors bear the loss proportionally without any fee deduction.

## Overview

AMEND Protocol is a smart contract system that enables pooled capital deployment with strict accountability. Users deposit assets into an ERC4626-compliant vault, which are then deployed by authorized managers to whitelisted investment destinations. Returns are reported transparently, and fees are only extracted from genuine profits.

The protocol enforces mathematical guarantees:
- Fees are never charged on principal or during loss periods
- Loss amounts cannot exceed invested capital
- Profit must be backed by actual on-chain assets before reporting

## Architecture

### AmendVault (ERC4626)

The vault manages user deposits and share accounting. It implements the standard ERC4626 tokenized vault interface with extensions for:
- Investment tracking via `investedAssets`
- Profit reporting with fee extraction
- Loss reporting without fees
- Engine-restricted operations

### AmendEngine (RBAC + Whitelist)

The engine manages capital deployment with role-based access control:

| Role | Responsibility |
|------|---------------|
| ADMIN_ROLE | Whitelist management, pause control |
| MANAGER_ROLE | Fund deployment and recall |
| REPORTER_ROLE | Profit and loss settlement |

Only whitelisted destinations can receive deployed funds. The engine maintains atomic accounting of deployed amounts.

## Security Model

### Trust Assumptions

1. **Vault Owner** - Controls engine assignment and fee parameters. Must be a multisig for production.
2. **Engine Admin** - Controls destination whitelist and emergency functions. Must be a multisig.
3. **Engine Manager** - Deploys and recalls funds. Can be automated or multisig-controlled.
4. **Engine Reporter** - Reports P&L. Can be automated keeper for frequent settlements.
5. **Destinations** - External contracts receiving funds. Must be vetted off-chain.

### Engine Authority

The engine has full authority over vault investment operations. A compromised engine could:
- Deploy funds to malicious destinations (mitigated by whitelist)
- Delay fund returns (operational risk)

The engine cannot:
- Report unbacked profits (blocked by on-chain balance verification)
- Report losses exceeding invested amount (blocked by accounting check)
- Extract fees on losses (blocked by invariant)

### Protections Implemented

- ReentrancyGuard on all fund-moving functions
- Pausable for emergency stops
- SafeERC20 for token operations
- AccessControl with role separation
- Whitelist for destination addresses
- Checks-Effects-Interactions pattern

## Status

**Version 0.1.1** - Production Ready

- Core contracts implemented and tested
- 60 tests passing (unit, fuzz, integration)
- Ready for external security audit
- Ready for testnet deployment

## Deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for deployment instructions.

### Quick Start

```bash
# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test -vv

# Deploy to testnet
source .env
forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC --broadcast
```

## Audit Readiness

See [docs/AUDIT_CHECKLIST.md](docs/AUDIT_CHECKLIST.md) for:
- Contract inventory
- Core invariants with code references
- Access control matrices
- Test coverage summary
- Known limitations

## Operations

See [docs/OPERATOR_MANUAL.md](docs/OPERATOR_MANUAL.md) for:
- Role definitions and responsibilities
- Daily operations checklists
- Capital deployment procedures
- Emergency procedures

## Contract Addresses

### Base Sepolia (Testnet)

Not yet deployed.

### Base Mainnet

Not yet deployed.

## License

MIT
