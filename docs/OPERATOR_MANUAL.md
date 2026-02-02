# AMEND Protocol v0.1.1 - Operator Manual

## Table of Contents

1. [Role Definitions](#role-definitions)
2. [Daily Operations](#daily-operations)
3. [Capital Deployment Flow](#capital-deployment-flow)
4. [Profit & Loss Reporting](#profit--loss-reporting)
5. [Emergency Procedures](#emergency-procedures)
6. [Monitoring & Alerts](#monitoring--alerts)

---

## Role Definitions

### Overview

The AMEND Protocol uses role-based access control with four distinct roles:

| Role | Responsibility | Typical Assignment |
|------|---------------|-------------------|
| **Vault Owner** | Protocol governance | Multisig (e.g., Safe) |
| **Engine Admin** | Whitelist & pause control | Multisig (e.g., Safe) |
| **Engine Manager** | Fund deployment | Investment team |
| **Engine Reporter** | P&L settlement | Keeper/bot or trusted operator |

### Vault Owner (Ownable)

**Capabilities:**
- Set Engine address (`setEngine`)
- Update fee parameters (`setFeeParams`)
- Rescue accidentally sent tokens (`rescueTokens`)
- Transfer ownership (`transferOwnership`)

**Security:** Always use multisig. Never use EOA for production.

### Engine Admin (ADMIN_ROLE)

**Capabilities:**
- Add destinations to whitelist (`addToWhitelist`)
- Remove destinations from whitelist (`removeFromWhitelist`)
- Pause all operations (`pause`)
- Resume operations (`unpause`)
- Emergency recall (`emergencyRecall`)
- Grant/revoke other roles

**Security:** Use multisig. Critical for protocol safety.

### Engine Manager (MANAGER_ROLE)

**Capabilities:**
- Deploy funds to destinations (`deployFunds`)
- Recall funds from destinations (`recallFunds`)
- Emergency recall (`emergencyRecall`)

**Security:** Can be EOA but recommend multisig or automated system.

### Engine Reporter (REPORTER_ROLE)

**Capabilities:**
- Report profit (`settleProfit`)
- Report loss (`settleLoss`)

**Security:** Can be automated keeper for frequent settlements.

---

## Daily Operations

### Morning Checklist

```bash
# 1. Check system health
cast call $ENGINE "isPaused()" --rpc-url $RPC_URL

# 2. Check total deployed
cast call $ENGINE "getTotalDeployed()" --rpc-url $RPC_URL

# 3. Check vault NAV
cast call $VAULT "totalAssets()" --rpc-url $RPC_URL

# 4. Check vault on-chain balance
cast call $USDC "balanceOf(address)" $VAULT --rpc-url $RPC_URL

# 5. Check invested assets accounting
cast call $VAULT "investedAssets()" --rpc-url $RPC_URL
```

### Accounting Verification

**Invariant Check:**
```bash
# These should be equal:
# Vault.totalAssets() == USDC.balanceOf(Vault) + Vault.investedAssets()

TOTAL=$(cast call $VAULT "totalAssets()" --rpc-url $RPC_URL)
BALANCE=$(cast call $USDC "balanceOf(address)" $VAULT --rpc-url $RPC_URL)
INVESTED=$(cast call $VAULT "investedAssets()" --rpc-url $RPC_URL)

# Calculate and verify
echo "Total Assets: $TOTAL"
echo "On-chain Balance: $BALANCE"
echo "Invested Assets: $INVESTED"
echo "Balance + Invested: $((BALANCE + INVESTED))"
```

---

## Capital Deployment Flow

### Pre-Deployment Checklist

1. [ ] Destination is whitelisted
2. [ ] Vault has sufficient idle assets
3. [ ] Destination approval process complete
4. [ ] Risk assessment documented

### Step 1: Check Available Capital

```bash
# Get total vault assets
TOTAL=$(cast call $VAULT "totalAssets()" --rpc-url $RPC_URL)

# Get currently invested
INVESTED=$(cast call $VAULT "investedAssets()" --rpc-url $RPC_URL)

# Available = Total - Invested
echo "Available for deployment: $((TOTAL - INVESTED))"
```

### Step 2: Verify Whitelist Status

```bash
cast call $ENGINE "isWhitelisted(address)" $DESTINATION --rpc-url $RPC_URL
# Returns: true (0x01) or false (0x00)
```

### Step 3: Deploy Funds

```bash
# As MANAGER
cast send $ENGINE \
  "deployFunds(address,uint256)" \
  $DESTINATION \
  $AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $MANAGER_KEY
```

### Step 4: Verify Deployment

```bash
# Check deployed amount
cast call $ENGINE "getDeployedTo(address)" $DESTINATION --rpc-url $RPC_URL

# Check total deployed
cast call $ENGINE "getTotalDeployed()" --rpc-url $RPC_URL

# Check vault invested assets updated
cast call $VAULT "investedAssets()" --rpc-url $RPC_URL
```

---

## Profit & Loss Reporting

### Profit Settlement Flow

**When:** Investment period ends with positive return

**Prerequisites:**
- Funds recalled from destination
- Profit amount transferred to Engine

```
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│  Destination  │───►│    Engine     │───►│     Vault     │
│  (has profit) │    │ (holds profit)│    │(receives prof)│
└───────────────┘    └───────────────┘    └───────────────┘
        │                    │                    │
   1. Recall funds      2. Transfer profit    3. reportProfit()
   (principal + P)      to Vault              triggers fee
```

**Step-by-Step:**

```bash
# 1. Recall principal from destination (Manager)
cast send $ENGINE \
  "recallFunds(address,uint256)" \
  $DESTINATION \
  $PRINCIPAL \
  --rpc-url $RPC_URL \
  --private-key $MANAGER_KEY

# 2. Destination transfers profit to Engine
# (Destination must do this - off-chain coordination)

# 3. Verify Engine received profit
cast call $USDC "balanceOf(address)" $ENGINE --rpc-url $RPC_URL

# 4. Settle profit (Reporter)
cast send $ENGINE \
  "settleProfit(uint256)" \
  $PROFIT_AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $REPORTER_KEY
```

### Loss Settlement Flow

**When:** Investment period ends with negative return

**IMPORTANT: NO FEE IS CHARGED ON LOSS**

```bash
# 1. Recall remaining funds from destination (Manager)
# If invested 1000, lost 200 → recall 800
cast send $ENGINE \
  "recallFunds(address,uint256)" \
  $DESTINATION \
  $REMAINING \
  --rpc-url $RPC_URL \
  --private-key $MANAGER_KEY

# 2. Report loss (Reporter)
cast send $ENGINE \
  "settleLoss(uint256)" \
  $LOSS_AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $REPORTER_KEY
```

### Settlement Verification

After any settlement:

```bash
# Verify NAV updated correctly
cast call $VAULT "totalAssets()" --rpc-url $RPC_URL

# Verify invested assets cleared (if fully settled)
cast call $VAULT "investedAssets()" --rpc-url $RPC_URL

# Check treasury shares (should only increase on profit)
cast call $VAULT "balanceOf(address)" $FEE_RECIPIENT --rpc-url $RPC_URL
```

---

## Emergency Procedures

### Level 1: Pause Protocol

**When:** Suspected exploit, market crash, or anomaly detected

**Who:** ADMIN

```bash
cast send $ENGINE \
  "pause()" \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_KEY
```

**Effects:**
- `deployFunds` → REVERTS
- `recallFunds` → REVERTS
- `settleProfit` → REVERTS
- `settleLoss` → REVERTS
- `emergencyRecall` → STILL WORKS

### Level 2: Emergency Recall

**When:** Need to pull all funds from a destination immediately

**Who:** ADMIN or MANAGER

```bash
# Prerequisites: Destination must have approved Engine
cast send $ENGINE \
  "emergencyRecall(address)" \
  $DESTINATION \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_KEY
```

### Level 3: Rotate Engine

**When:** Engine compromised, need to replace

**Who:** VAULT OWNER

**Process:**

1. **Pause current Engine:**
   ```bash
   cast send $ENGINE_OLD "pause()" --rpc-url $RPC_URL --private-key $ADMIN_KEY
   ```

2. **Emergency recall from all destinations:**
   ```bash
   for DEST in $DESTINATIONS; do
     cast send $ENGINE_OLD "emergencyRecall(address)" $DEST --rpc-url $RPC_URL --private-key $ADMIN_KEY
   done
   ```

3. **Deploy new Engine:**
   ```bash
   forge create src/AmendEngine.sol:AmendEngine \
     --constructor-args $VAULT $NEW_ADMIN \
     --rpc-url $RPC_URL \
     --private-key $DEPLOYER_KEY
   ```

4. **Update Vault to use new Engine:**
   ```bash
   cast send $VAULT \
     "setEngine(address)" \
     $ENGINE_NEW \
     --rpc-url $RPC_URL \
     --private-key $OWNER_KEY
   ```

5. **Setup new Engine:**
   - Grant roles
   - Add destinations to whitelist
   - Resume operations

### Level 4: Full Recovery Mode

**When:** Critical vulnerability, protocol-wide issue

1. Pause Engine
2. Emergency recall all funds
3. Users withdraw from Vault
4. Investigate and fix
5. Redeploy if necessary

---

## Monitoring & Alerts

### Key Metrics

| Metric | Normal | Warning | Critical |
|--------|--------|---------|----------|
| Engine.isPaused() | false | - | true |
| Vault.totalAssets() | Growing | Flat | Decreasing |
| Engine.totalDeployed() | < 80% NAV | 80-95% NAV | > 95% NAV |
| Fee Recipient Balance | Growing | Flat | - |

### Recommended Alerts

1. **Engine Paused**
   - Severity: CRITICAL
   - Action: Investigate immediately

2. **Large Deployment (>10% NAV)**
   - Severity: WARNING
   - Action: Verify authorization

3. **Loss Reported**
   - Severity: INFO
   - Action: Document and review

4. **New Whitelist Addition**
   - Severity: INFO
   - Action: Verify destination legitimacy

5. **Role Change**
   - Severity: WARNING
   - Action: Verify authorization

### Log Events to Monitor

```solidity
// Engine Events
event WhitelistAdded(address indexed destination);
event WhitelistRemoved(address indexed destination);
event FundsDeployed(address indexed destination, uint256 amount);
event FundsRecalled(address indexed destination, uint256 amount);
event EmergencyRecall(address indexed destination, uint256 amount);
event ProfitSettled(uint256 profitAmount);
event LossSettled(uint256 lossAmount);
event Paused(address account);
event Unpaused(address account);

// Vault Events
event EngineUpdated(address indexed newEngine);
event FeeParamsUpdated(address indexed feeRecipient, uint16 feeBps);
event Invested(uint256 assets);
event Divested(uint256 assetsReturned);
event ProfitReported(uint256 grossProfit, uint256 feeAssets);
event LossReported(uint256 lossAssets);
```

### Sample Monitoring Script

```bash
#!/bin/bash
# monitor.sh - Basic monitoring script

RPC_URL="https://mainnet.base.org"
ENGINE="0x..."
VAULT="0x..."

# Check pause status
PAUSED=$(cast call $ENGINE "isPaused()" --rpc-url $RPC_URL)
if [ "$PAUSED" = "0x01" ]; then
  echo "CRITICAL: Engine is PAUSED!"
fi

# Check NAV
NAV=$(cast call $VAULT "totalAssets()" --rpc-url $RPC_URL)
echo "Current NAV: $NAV"

# Check deployed ratio
DEPLOYED=$(cast call $ENGINE "getTotalDeployed()" --rpc-url $RPC_URL)
RATIO=$((DEPLOYED * 100 / NAV))
if [ $RATIO -gt 95 ]; then
  echo "WARNING: High deployment ratio: $RATIO%"
fi
```

---

## Troubleshooting

### Common Issues

**"NotWhitelisted" Error**
- Cause: Destination not in whitelist
- Solution: Admin must call `addToWhitelist()`

**"RecallExceedsDeployed" Error**
- Cause: Trying to recall more than deployed
- Solution: Check `getDeployedTo()` and adjust amount

**"ProfitNotBacked" Error**
- Cause: Engine doesn't have profit amount in balance
- Solution: Ensure profit transferred to Engine before `settleProfit()`

**"ContractPaused" Error**
- Cause: Engine is paused
- Solution: Admin must call `unpause()` after emergency resolved

**"loss > invested" Error**
- Cause: Reporting loss greater than invested amount
- Solution: Check `vault.investedAssets()` and adjust loss amount

---

## Contact & Escalation

- **Normal Operations:** Operations Team
- **Security Issues:** Security Team (immediately)
- **Smart Contract Issues:** Engineering Team

---

*AMEND Protocol v0.1.1 Operator Manual*
*Core Invariant: "NO FEE ON LOSS"*
