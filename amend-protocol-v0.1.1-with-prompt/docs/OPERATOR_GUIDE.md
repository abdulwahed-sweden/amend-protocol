# AMEND Protocol - Operator Guide

## Overview

This guide is for operators responsible for managing the AMEND Protocol's investment engine. Operators include:

- **ADMIN**: Manages whitelist and emergency controls
- **MANAGER**: Deploys and recalls funds
- **REPORTER**: Reports profit/loss to settle with the Vault

## Role Responsibilities

### ADMIN Role

| Responsibility | Function | When to Use |
|---------------|----------|-------------|
| Add investment destination | `addToWhitelist(address)` | Before deploying funds to new address |
| Remove destination | `removeFromWhitelist(address)` | After recalling all funds from address |
| Emergency pause | `pause()` | Security incident or market emergency |
| Resume operations | `unpause()` | After emergency is resolved |
| Grant/revoke roles | `grantRole()` / `revokeRole()` | Onboarding/offboarding operators |

### MANAGER Role

| Responsibility | Function | When to Use |
|---------------|----------|-------------|
| Deploy capital | `deployFunds(destination, amount)` | Investing vault funds |
| Recall capital | `recallFunds(destination, amount)` | Returning funds to vault |
| Emergency recall | `emergencyRecall(destination)` | Immediate full withdrawal |

### REPORTER Role

| Responsibility | Function | When to Use |
|---------------|----------|-------------|
| Report profit | `settleProfit(profitAmount)` | After profitable period |
| Report loss | `settleLoss(lossAmount)` | After unprofitable period |

## Daily Operations

### Deploying Funds

**Prerequisites:**
1. Destination must be whitelisted
2. Vault must have sufficient idle assets

**Process:**
```bash
# Check vault balance
cast call $VAULT "totalAssets()" --rpc-url $RPC_URL
cast call $VAULT "investedAssets()" --rpc-url $RPC_URL

# Calculate available (idle) assets
# available = totalAssets - investedAssets

# Deploy funds
cast send $ENGINE "deployFunds(address,uint256)" \
  $DESTINATION \
  $AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $MANAGER_KEY
```

**Verification:**
```bash
# Check deployment recorded
cast call $ENGINE "getDeployedTo(address)" $DESTINATION --rpc-url $RPC_URL
cast call $ENGINE "getTotalDeployed()" --rpc-url $RPC_URL
```

### Recalling Funds

**Prerequisites:**
1. Destination must approve Engine to pull funds
2. Amount must not exceed deployed amount

**Process:**

1. **Request approval from destination** (off-chain coordination)

2. **Verify approval:**
   ```bash
   cast call $USDC "allowance(address,address)" $DESTINATION $ENGINE --rpc-url $RPC_URL
   ```

3. **Recall funds:**
   ```bash
   cast send $ENGINE "recallFunds(address,uint256)" \
     $DESTINATION \
     $AMOUNT \
     --rpc-url $RPC_URL \
     --private-key $MANAGER_KEY
   ```

### Settling Profit

**When:** After an investment period ends with profit

**Prerequisites:**
- Funds must be recalled first
- Profit must be transferred to Engine
- Engine balance must be >= profit amount

**Process:**

1. **Recall original capital:**
   ```bash
   cast send $ENGINE "recallFunds(address,uint256)" $DESTINATION $PRINCIPAL --rpc-url $RPC_URL --private-key $MANAGER_KEY
   ```

2. **Transfer profit to Engine** (destination sends profit):
   ```bash
   # Destination calls:
   cast send $USDC "transfer(address,uint256)" $ENGINE $PROFIT --rpc-url $RPC_URL --private-key $DESTINATION_KEY
   ```

3. **Verify Engine balance:**
   ```bash
   cast call $USDC "balanceOf(address)" $ENGINE --rpc-url $RPC_URL
   ```

4. **Settle profit:**
   ```bash
   cast send $ENGINE "settleProfit(uint256)" $PROFIT --rpc-url $RPC_URL --private-key $REPORTER_KEY
   ```

### Settling Loss

**When:** After an investment period ends with loss

**IMPORTANT: NO FEE IS CHARGED ON LOSS**

**Process:**

1. **Recall remaining funds:**
   ```bash
   # If deployed 1000, lost 200, recall 800
   cast send $ENGINE "recallFunds(address,uint256)" $DESTINATION 800 --rpc-url $RPC_URL --private-key $MANAGER_KEY
   ```

2. **Report loss:**
   ```bash
   cast send $ENGINE "settleLoss(uint256)" 200 --rpc-url $RPC_URL --private-key $REPORTER_KEY
   ```

## Emergency Procedures

### Pausing the Protocol

**When:** Security vulnerability discovered, or market black swan event

```bash
cast send $ENGINE "pause()" --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

**Effects:**
- `deployFunds()` will revert
- `recallFunds()` will revert
- `settleProfit()` will revert
- `settleLoss()` will revert
- `emergencyRecall()` still works

### Emergency Recall

**When:** Immediate full withdrawal needed from a destination

```bash
cast send $ENGINE "emergencyRecall(address)" $DESTINATION --rpc-url $RPC_URL --private-key $ADMIN_OR_MANAGER_KEY
```

**Note:** Destination must have approved Engine for the full deployed amount.

### Resuming Operations

```bash
cast send $ENGINE "unpause()" --rpc-url $RPC_URL --private-key $ADMIN_KEY
```

## Monitoring

### Key Metrics to Track

1. **Vault Health**
   ```bash
   # Total NAV
   cast call $VAULT "totalAssets()"

   # On-chain balance
   cast call $USDC "balanceOf(address)" $VAULT

   # Invested assets
   cast call $VAULT "investedAssets()"
   ```

2. **Engine Accounting**
   ```bash
   # Total deployed
   cast call $ENGINE "getTotalDeployed()"

   # Per-destination
   cast call $ENGINE "getDeployedTo(address)" $DESTINATION
   ```

3. **Pause State**
   ```bash
   cast call $ENGINE "isPaused()"
   ```

### Alerts to Configure

| Condition | Severity | Action |
|-----------|----------|--------|
| Engine paused | HIGH | Investigate immediately |
| Large deployment (>10% NAV) | MEDIUM | Verify authorization |
| Loss reported | MEDIUM | Review investment performance |
| New whitelist addition | INFO | Confirm legitimate destination |

## Accounting Best Practices

### Invariant Checks

Run these periodically to verify system health:

```bash
# Check accounting invariant
DEPLOYED_1=$(cast call $ENGINE "getDeployedTo(address)" $DEST1 --rpc-url $RPC_URL)
DEPLOYED_2=$(cast call $ENGINE "getDeployedTo(address)" $DEST2 --rpc-url $RPC_URL)
TOTAL=$(cast call $ENGINE "getTotalDeployed()" --rpc-url $RPC_URL)

# TOTAL should equal DEPLOYED_1 + DEPLOYED_2 + ...
```

### Record Keeping

Maintain off-chain records of:
- All deployment transactions (tx hash, amount, destination, timestamp)
- All recall transactions
- All profit/loss settlements
- Destination approval statuses

### Reconciliation

Weekly:
1. Compare on-chain deployed amounts with destination balances
2. Calculate unrealized P&L
3. Verify NAV = on-chain balance + invested assets

## Troubleshooting

### "NotWhitelisted" Error
**Cause:** Attempting to deploy to non-whitelisted address
**Solution:** Admin must first call `addToWhitelist(destination)`

### "RecallExceedsDeployed" Error
**Cause:** Recalling more than deployed amount
**Solution:** Check `getDeployedTo(destination)` and reduce recall amount

### "ProfitNotBacked" Error
**Cause:** Engine doesn't have enough assets to back reported profit
**Solution:** Ensure profit has been transferred to Engine before calling `settleProfit()`

### "ContractPaused" Error
**Cause:** Engine is paused
**Solution:** Admin must call `unpause()` (only after emergency is resolved)

### "CannotRemoveWithDeployedFunds" Error
**Cause:** Attempting to remove whitelisted address that has deployed funds
**Solution:** Recall all funds first, then remove from whitelist

## Security Reminders

1. **Never** share private keys via insecure channels
2. **Always** verify transaction details before signing
3. **Use** hardware wallets for high-value operations
4. **Monitor** for unusual activity continuously
5. **Report** any suspicious behavior to the security team
6. **Double-check** addresses before any fund transfers

---

*AMEND Protocol Operator Guide v0.1.1*
*Core Invariant: "NO FEE ON LOSS"*
