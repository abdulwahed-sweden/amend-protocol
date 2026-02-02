# AMEND Protocol - Deployment Guide

## Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`)
- Access to an Ethereum RPC endpoint
- Private key with sufficient ETH for gas
- USDC contract address for the target network

## Network Configuration

### Base Mainnet
```
USDC: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
Chain ID: 8453
RPC: https://mainnet.base.org
```

### Base Sepolia (Testnet)
```
USDC: 0x036CbD53842c5426634e7929541eC2318f3dCF7e
Chain ID: 84532
RPC: https://sepolia.base.org
```

## Deployment Steps

### 1. Configure Environment

Create a `.env` file (never commit this):

```bash
# .env
PRIVATE_KEY=your_deployer_private_key
RPC_URL=https://mainnet.base.org
ETHERSCAN_API_KEY=your_basescan_api_key

# Deployment parameters
VAULT_NAME="AMEND Vault"
VAULT_SYMBOL="avUSDC"
FEE_RECIPIENT=0x...  # Treasury multisig
FEE_BPS=1000         # 10% fee on profit
ADMIN_ADDRESS=0x...  # Engine admin multisig
```

### 2. Deploy Vault

```bash
source .env

forge create src/AmendVault.sol:AmendVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args \
    $USDC_ADDRESS \
    "$VAULT_NAME" \
    "$VAULT_SYMBOL" \
    $DEPLOYER_ADDRESS \
    $FEE_RECIPIENT \
    $FEE_BPS \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Save the deployed Vault address: `VAULT_ADDRESS=0x...`

### 3. Deploy Engine

```bash
forge create src/AmendEngine.sol:AmendEngine \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --constructor-args \
    $VAULT_ADDRESS \
    $ADMIN_ADDRESS \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

Save the deployed Engine address: `ENGINE_ADDRESS=0x...`

### 4. Link Engine to Vault

The Vault owner must call `setEngine()`:

```bash
cast send $VAULT_ADDRESS \
  "setEngine(address)" $ENGINE_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $OWNER_PRIVATE_KEY
```

### 5. Configure Engine Roles

Using the admin account:

```bash
# Grant MANAGER_ROLE to investment manager
cast send $ENGINE_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak "MANAGER_ROLE") \
  $MANAGER_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_PRIVATE_KEY

# Grant REPORTER_ROLE to settlement system
cast send $ENGINE_ADDRESS \
  "grantRole(bytes32,address)" \
  $(cast keccak "REPORTER_ROLE") \
  $REPORTER_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_PRIVATE_KEY
```

### 6. Whitelist Investment Destinations

```bash
cast send $ENGINE_ADDRESS \
  "addToWhitelist(address)" \
  $DESTINATION_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $ADMIN_PRIVATE_KEY
```

## Verification Checklist

After deployment, verify:

```bash
# Check Vault state
cast call $VAULT_ADDRESS "engine()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "feeRecipient()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "managementFeeBps()" --rpc-url $RPC_URL

# Check Engine state
cast call $ENGINE_ADDRESS "vault()" --rpc-url $RPC_URL
cast call $ENGINE_ADDRESS "asset()" --rpc-url $RPC_URL

# Check roles
cast call $ENGINE_ADDRESS "hasRole(bytes32,address)" \
  $(cast keccak "ADMIN_ROLE") $ADMIN_ADDRESS \
  --rpc-url $RPC_URL
```

## Deployment Script (Alternative)

For automated deployment, create `script/Deploy.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AmendVault} from "../src/AmendVault.sol";
import {AmendEngine} from "../src/AmendEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint16 feeBps = uint16(vm.envUint("FEE_BPS"));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Vault
        AmendVault vault = new AmendVault(
            IERC20(usdc),
            "AMEND Vault",
            "avUSDC",
            msg.sender,
            feeRecipient,
            feeBps
        );

        // Deploy Engine
        AmendEngine engine = new AmendEngine(
            address(vault),
            admin
        );

        // Link Engine to Vault
        vault.setEngine(address(engine));

        vm.stopBroadcast();
    }
}
```

Run with:
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify
```

## Post-Deployment

1. **Transfer Vault ownership** to a multisig:
   ```bash
   cast send $VAULT_ADDRESS "transferOwnership(address)" $MULTISIG --rpc-url $RPC_URL --private-key $OWNER_KEY
   ```

2. **Renounce deployer's DEFAULT_ADMIN_ROLE** from Engine (after setup):
   ```bash
   cast send $ENGINE_ADDRESS "renounceRole(bytes32,address)" $(cast keccak "DEFAULT_ADMIN_ROLE") $DEPLOYER --rpc-url $RPC_URL --private-key $DEPLOYER_KEY
   ```

3. **Document all deployed addresses** in a secure location

4. **Test with small amounts** before opening to users

## Security Notes

- Never commit private keys or `.env` files
- Use hardware wallets for production deployments
- Verify all contract source code on block explorers
- Consider using CREATE2 for deterministic addresses
- Perform a security audit before mainnet deployment
