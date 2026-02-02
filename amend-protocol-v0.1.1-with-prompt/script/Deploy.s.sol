// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AmendVault } from "../src/AmendVault.sol";
import { AmendEngine } from "../src/AmendEngine.sol";
import { DeployConfig } from "./DeployConfig.sol";

/**
 * @title Deploy
 * @notice Deployment script for AMEND Protocol v0.1.1
 * @dev Deploys AmendVault and AmendEngine, then links them together
 *
 * Usage:
 *   # Testnet (Base Sepolia)
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
 *
 *   # Mainnet (Base) - USE WITH CAUTION
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_MAINNET_RPC --broadcast --verify
 *
 * Required Environment Variables:
 *   - PRIVATE_KEY: Deployer private key
 *   - ADMIN_ADDRESS: Engine admin address (multisig recommended)
 *   - FEE_RECIPIENT: Treasury address for fee collection
 *   - FEE_BPS: Fee in basis points (optional, default 1000 = 10%)
 *   - USDC_ADDRESS: (optional) Override USDC address
 */
contract Deploy is Script, DeployConfig {
    // ============ Deployment State ============

    AmendVault public vault;
    AmendEngine public engine;

    // ============ Main Deployment ============

    function run() external virtual {
        // ═══════════════════════════════════════════════════════════════════
        // STEP 1: Load Configuration
        // ═══════════════════════════════════════════════════════════════════

        console.log("========================================");
        console.log("AMEND Protocol v0.1.1 Deployment");
        console.log("========================================");
        console.log("");

        NetworkConfig memory config = getConfigByChainId();
        console.log("Network:", config.networkName);
        console.log("Chain ID:", block.chainid);
        console.log("");

        // Override from environment variables
        config = _applyEnvOverrides(config);

        // Validate configuration
        validateConfig(config);
        console.log("Configuration validated successfully");
        console.log("");

        // Log configuration (without sensitive data)
        console.log("--- Configuration ---");
        console.log("USDC Address:", config.usdc);
        console.log("Admin Address:", config.admin);
        console.log("Fee Recipient:", config.feeRecipient);
        console.log("Fee (bps):", config.feeBps);
        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // STEP 2: Begin Deployment
        // ═══════════════════════════════════════════════════════════════════

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("--- Deployer ---");
        console.log("Address:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ═══════════════════════════════════════════════════════════════════
        // STEP 3: Deploy AmendVault
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Deploying AmendVault ---");

        vault = new AmendVault(
            IERC20(config.usdc),
            "AMEND Vault",
            "avUSDC",
            deployer, // Owner is deployer initially
            config.feeRecipient,
            config.feeBps
        );

        console.log("AmendVault deployed at:", address(vault));
        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // STEP 4: Deploy AmendEngine
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Deploying AmendEngine ---");

        engine = new AmendEngine(address(vault), config.admin);

        console.log("AmendEngine deployed at:", address(engine));
        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: Link Engine to Vault
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Linking Engine to Vault ---");

        vault.setEngine(address(engine));

        console.log("Engine linked successfully");
        console.log("");

        vm.stopBroadcast();

        // ═══════════════════════════════════════════════════════════════════
        // STEP 6: Output Summary
        // ═══════════════════════════════════════════════════════════════════

        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("--- Contract Addresses ---");
        console.log("AmendVault:", address(vault));
        console.log("AmendEngine:", address(engine));
        console.log("");
        console.log("--- Verification Commands ---");
        console.log("Run these after deployment:");
        console.log("");
        _logVerificationCommands(config);
        console.log("");
        console.log("--- Post-Deployment Checklist ---");
        console.log("[ ] Verify contracts on block explorer");
        console.log("[ ] Transfer Vault ownership to multisig");
        console.log("[ ] Grant MANAGER_ROLE to investment managers");
        console.log("[ ] Grant REPORTER_ROLE to settlement systems");
        console.log("[ ] Add investment destinations to whitelist");
        console.log("[ ] Test with small deposit before announcing");
        console.log("");
    }

    // ============ Helper Functions ============

    /**
     * @dev Apply environment variable overrides to configuration
     */
    function _applyEnvOverrides(NetworkConfig memory config) internal view returns (NetworkConfig memory) {
        // Required overrides
        config.admin = vm.envAddress("ADMIN_ADDRESS");
        config.feeRecipient = vm.envAddress("FEE_RECIPIENT");

        // Optional overrides
        try vm.envUint("FEE_BPS") returns (uint256 feeBps) {
            config.feeBps = uint16(feeBps);
        } catch {
            // Keep default from config
        }

        try vm.envAddress("USDC_ADDRESS") returns (address usdc) {
            if (usdc != address(0)) {
                config.usdc = usdc;
            }
        } catch {
            // Keep default from config
        }

        return config;
    }

    /**
     * @dev Log verification commands for post-deployment
     */
    function _logVerificationCommands(NetworkConfig memory config) internal view {
        console.log("# Verify Vault");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm_toString(uint256(uint160(address(vault)))),
                " src/AmendVault.sol:AmendVault --chain ",
                vm_toString(block.chainid)
            )
        );
        console.log("");
        console.log("# Verify Engine");
        console.log(
            string.concat(
                "forge verify-contract ",
                vm_toString(uint256(uint160(address(engine)))),
                " src/AmendEngine.sol:AmendEngine --chain ",
                vm_toString(block.chainid)
            )
        );
    }
}

