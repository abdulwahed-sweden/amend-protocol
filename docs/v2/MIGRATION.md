# Migration Guide: v0.1.1 → v0.2.0

## Important Notice

v0.2.0 is **NOT** an upgrade to v0.1.1.
These are separate, parallel deployments with different architectures.

## Why No Automatic Migration?

1. **Different Contract Addresses**
   - New deployment = new addresses
   - ERC4626 shares are not transferable between vaults

2. **Different Settlement Architecture**
   - v0.1.1: Engine pushes → `divest()` + `reportProfit()`
   - v0.2.0: Vault pulls → `repay()`

3. **Incompatible Internal Accounting**
   - Different event structures
   - Different role hierarchies

## Migration Steps

### For Protocol Operators

1. **Announce Migration Window**
   - Notify users 14-30 days in advance
   - Publish migration timeline

2. **Pause v0.1.1 New Deposits** (Optional)
   - Prevents new capital entering old vault
   - Existing users can still withdraw

3. **Deploy v0.2.0 Contracts**
   ```bash
   forge script script/DeployV2.s.sol --rpc-url $RPC_URL --broadcast
   ```

4. **Verify v0.2.0 Contracts**
   - Verify on block explorer
   - Run verification scripts

5. **Setup v0.2.0 Roles**
   - Grant OPERATOR_ROLE to managers
   - Grant REPORTER_ROLE to settlement systems
   - Grant EMERGENCY_ROLE to security team

6. **Whitelist Destinations**
   - Re-add trusted destinations to v0.2.0 engine

### For Users

1. **Withdraw from v0.1.1**
   ```solidity
   // Get your share balance
   uint256 shares = vaultV1.balanceOf(msg.sender);

   // Redeem all shares
   vaultV1.redeem(shares, msg.sender, msg.sender);
   ```

2. **Deposit to v0.2.0**
   ```solidity
   // Approve new vault
   usdc.approve(address(vaultV2), amount);

   // Deposit to new vault
   vaultV2.deposit(amount, msg.sender);
   ```

## Timeline Recommendation

| Day | Action |
|-----|--------|
| D-30 | Announce migration |
| D-14 | Deploy v0.2.0 to testnet |
| D-7 | Final testing |
| D-0 | Deploy v0.2.0 to mainnet |
| D+1 | Begin migration window |
| D+30 | End migration window |
| D+60 | Consider sunsetting v0.1.1 |

## Parallel Operation

Both vaults can operate simultaneously:

- v0.1.1: Continue serving existing users
- v0.2.0: Accept new deposits

This allows:
- Gradual migration
- No forced urgency
- User choice

## What Stays the Same

- Underlying asset (USDC)
- ERC4626 interface
- "NO FEE ON LOSS" invariant
- Fee structure (configurable)
- Whitelist-based deployment

## What Changes

| Feature | v0.1.1 | v0.2.0 |
|---------|--------|--------|
| Settlement | Two-step (push) | Atomic (pull) |
| Admin Role | ADMIN_ROLE | DEFAULT_ADMIN_ROLE |
| Manager Role | MANAGER_ROLE | OPERATOR_ROLE |
| Pause Control | ADMIN_ROLE | EMERGENCY_ROLE |
| Profit Reporting | reportProfit() | repay() |
| Fund Return | divest() | repay() |

## Support

For migration assistance:
- Review documentation
- Test on Sepolia first
- Start with small amounts

---

*AMEND Protocol Migration Guide*
*Author: Abdulwahed Mansour*
