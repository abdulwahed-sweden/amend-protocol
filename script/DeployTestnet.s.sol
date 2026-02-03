// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {AmendVault} from "../src/AmendVault.sol";
import {AmendEngine} from "../src/AmendEngine.sol";

/**
 * @title DeployTestnet
 * @author Abdulwahed Mansour
 * @notice Deployment script for AMEND Protocol v0.1.1 on Base Sepolia
 * @dev Deploys MockERC20, AmendVault, and AmendEngine
 *
 * Usage:
 *   source .env
 *   forge script script/DeployTestnet.s.sol:DeployTestnet \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     -vvvv
 */
contract DeployTestnet is Script {
    // ============ Configuration ============
    string constant MOCK_TOKEN_NAME = "Mock USDC";
    string constant MOCK_TOKEN_SYMBOL = "mUSDC";
    uint8 constant MOCK_TOKEN_DECIMALS = 6;

    string constant VAULT_NAME = "AMEND Vault";
    string constant VAULT_SYMBOL = "avUSDC";
    uint16 constant FEE_BPS = 1000; // 10%

    // ============ Deployed Contracts ============
    MockERC20 public mockUSDC;
    AmendVault public vault;
    AmendEngine public engine;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("========================================");
        console.log("AMEND Protocol v0.1.1 - Testnet Deploy");
        console.log("========================================");
        console.log("");
        console.log("Deployer:", deployer);
        console.log("Network: Base Sepolia");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // ═══════════════════════════════════════════════════════════════════
        // STEP 1: Deploy Mock USDC
        // ═══════════════════════════════════════════════════════════════════
        console.log("Deploying MockERC20 (mUSDC)...");
        mockUSDC = new MockERC20(
            MOCK_TOKEN_NAME,
            MOCK_TOKEN_SYMBOL,
            MOCK_TOKEN_DECIMALS
        );
        console.log("MockERC20 deployed at:", address(mockUSDC));

        // ═══════════════════════════════════════════════════════════════════
        // STEP 2: Deploy AmendVault
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Deploying AmendVault...");
        vault = new AmendVault(
            IERC20(address(mockUSDC)),
            VAULT_NAME,
            VAULT_SYMBOL,
            deployer,        // owner
            deployer,        // feeRecipient (deployer for testnet)
            FEE_BPS
        );
        console.log("AmendVault deployed at:", address(vault));

        // ═══════════════════════════════════════════════════════════════════
        // STEP 3: Deploy AmendEngine
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Deploying AmendEngine...");
        engine = new AmendEngine(
            address(vault),
            deployer         // admin
        );
        console.log("AmendEngine deployed at:", address(engine));

        // ═══════════════════════════════════════════════════════════════════
        // STEP 4: Link Engine to Vault
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Linking Engine to Vault...");
        vault.setEngine(address(engine));
        console.log("Engine linked successfully");

        // ═══════════════════════════════════════════════════════════════════
        // STEP 5: Mint Test Tokens to Deployer
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("Minting 1,000,000 mUSDC to deployer...");
        mockUSDC.mint(deployer, 1_000_000 * 10**MOCK_TOKEN_DECIMALS);
        console.log("Minted successfully");

        vm.stopBroadcast();

        // ═══════════════════════════════════════════════════════════════════
        // SUMMARY
        // ═══════════════════════════════════════════════════════════════════
        console.log("");
        console.log("========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("");
        console.log("Contract Addresses:");
        console.log("  MockERC20 (mUSDC):", address(mockUSDC));
        console.log("  AmendVault:       ", address(vault));
        console.log("  AmendEngine:      ", address(engine));
        console.log("");
        console.log("Deployer Roles:");
        console.log("  Vault Owner:      ", deployer);
        console.log("  Engine Admin:     ", deployer);
        console.log("  Engine Manager:   ", deployer);
        console.log("  Engine Reporter:  ", deployer);
        console.log("");
        console.log("Next Steps:");
        console.log("  1. Verify contracts on BaseScan");
        console.log("  2. Add destinations to whitelist");
        console.log("  3. Test deposit/withdraw flow");
        console.log("");
    }
}
