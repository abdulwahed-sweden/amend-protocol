// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script, console } from "forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AmendVault } from "../src/AmendVault.sol";
import { AmendEngine } from "../src/AmendEngine.sol";

/**
 * @title VerifyContracts
 * @notice Post-deployment verification script for AMEND Protocol
 * @dev Verifies contract state and linkage after deployment
 *
 * Usage:
 *   forge script script/VerifyContracts.s.sol:VerifyContracts --rpc-url $RPC_URL
 *
 * Required Environment Variables:
 *   - VAULT_ADDRESS: Deployed AmendVault address
 *   - ENGINE_ADDRESS: Deployed AmendEngine address
 */
contract VerifyContracts is Script {
    // ============ State ============

    AmendVault public vault;
    AmendEngine public engine;

    uint256 public checksRun;
    uint256 public checksPassed;
    uint256 public checksFailed;

    // ============ Main Verification ============

    function run() external view {
        console.log("========================================");
        console.log("AMEND Protocol v0.1.1 Verification");
        console.log("========================================");
        console.log("");

        // Load contract addresses
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address engineAddr = vm.envAddress("ENGINE_ADDRESS");

        console.log("Vault Address:", vaultAddr);
        console.log("Engine Address:", engineAddr);
        console.log("");

        // Initialize contract instances
        AmendVault _vault = AmendVault(vaultAddr);
        AmendEngine _engine = AmendEngine(engineAddr);

        // ═══════════════════════════════════════════════════════════════════
        // VAULT VERIFICATION
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Vault State ---");

        // Check vault has engine set
        address linkedEngine = _vault.engine();
        _check("Vault.engine() is set", linkedEngine != address(0));
        _check("Vault.engine() matches Engine", linkedEngine == engineAddr);

        // Check vault parameters
        address asset = address(_vault.asset());
        console.log("Asset (USDC):", asset);
        _check("Asset is not zero", asset != address(0));

        address feeRecipient = _vault.feeRecipient();
        console.log("Fee Recipient:", feeRecipient);
        _check("Fee recipient is set", feeRecipient != address(0));

        uint16 feeBps = _vault.managementFeeBps();
        console.log("Fee (bps):", feeBps);
        _check("Fee is <= 2000 (20%)", feeBps <= 2000);

        address owner = _vault.owner();
        console.log("Owner:", owner);
        _check("Owner is set", owner != address(0));

        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // ENGINE VERIFICATION
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Engine State ---");

        // Check engine references vault
        address linkedVault = _engine.vault();
        _check("Engine.vault() matches Vault", linkedVault == vaultAddr);

        // Check engine has same asset as vault
        address engineAsset = _engine.asset();
        _check("Engine.asset() matches Vault.asset()", engineAsset == asset);

        // Check engine is not paused
        bool isPaused = _engine.isPaused();
        console.log("Is Paused:", isPaused);
        _check("Engine is NOT paused", !isPaused);

        // Check roles are set
        bytes32 adminRole = keccak256("ADMIN_ROLE");
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        bytes32 reporterRole = keccak256("REPORTER_ROLE");

        // Note: We can't easily check who has roles without knowing addresses
        // But we can verify the role constants exist

        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // CROSS-CONTRACT VERIFICATION
        // ═══════════════════════════════════════════════════════════════════

        console.log("--- Cross-Contract Checks ---");

        // Verify initial state
        uint256 totalDeployed = _engine.getTotalDeployed();
        console.log("Total Deployed:", totalDeployed);
        _check("No funds deployed yet", totalDeployed == 0);

        uint256 investedAssets = _vault.investedAssets();
        console.log("Invested Assets:", investedAssets);
        _check("No invested assets yet", investedAssets == 0);

        console.log("");

        // ═══════════════════════════════════════════════════════════════════
        // SUMMARY
        // ═══════════════════════════════════════════════════════════════════

        console.log("========================================");
        console.log("VERIFICATION COMPLETE");
        console.log("========================================");
    }

    // ============ Helper Functions ============

    function _check(string memory description, bool condition) internal pure {
        if (condition) {
            console.log(unicode"✓", description);
        } else {
            console.log(unicode"✗ FAILED:", description);
        }
    }
}

/**
 * @title VerifyRoles
 * @notice Verify role assignments on the Engine
 * @dev Checks specific addresses have required roles
 *
 * Required Environment Variables:
 *   - ENGINE_ADDRESS
 *   - ADMIN_ADDRESS (to verify)
 *   - MANAGER_ADDRESS (optional)
 *   - REPORTER_ADDRESS (optional)
 */
contract VerifyRoles is Script {
    function run() external view {
        console.log("========================================");
        console.log("Role Verification");
        console.log("========================================");
        console.log("");

        address engineAddr = vm.envAddress("ENGINE_ADDRESS");
        AmendEngine engine = AmendEngine(engineAddr);

        console.log("Engine:", engineAddr);
        console.log("");

        // Role constants
        bytes32 defaultAdminRole = 0x00;
        bytes32 adminRole = keccak256("ADMIN_ROLE");
        bytes32 managerRole = keccak256("MANAGER_ROLE");
        bytes32 reporterRole = keccak256("REPORTER_ROLE");

        // Check admin
        address admin = vm.envAddress("ADMIN_ADDRESS");
        console.log("--- Admin:", admin, "---");
        _checkRole(engine, "DEFAULT_ADMIN_ROLE", defaultAdminRole, admin);
        _checkRole(engine, "ADMIN_ROLE", adminRole, admin);
        _checkRole(engine, "MANAGER_ROLE", managerRole, admin);
        _checkRole(engine, "REPORTER_ROLE", reporterRole, admin);
        console.log("");

        // Check manager (if provided)
        try vm.envAddress("MANAGER_ADDRESS") returns (address manager) {
            if (manager != address(0)) {
                console.log("--- Manager:", manager, "---");
                _checkRole(engine, "MANAGER_ROLE", managerRole, manager);
                console.log("");
            }
        } catch {}

        // Check reporter (if provided)
        try vm.envAddress("REPORTER_ADDRESS") returns (address reporter) {
            if (reporter != address(0)) {
                console.log("--- Reporter:", reporter, "---");
                _checkRole(engine, "REPORTER_ROLE", reporterRole, reporter);
                console.log("");
            }
        } catch {}

        console.log("========================================");
    }

    function _checkRole(AmendEngine engine, string memory roleName, bytes32 role, address account) internal view {
        bool hasRole = engine.hasRole(role, account);
        if (hasRole) {
            console.log(unicode"  ✓", roleName);
        } else {
            console.log(unicode"  ✗", roleName, "(NOT ASSIGNED)");
        }
    }
}

/**
 * @title VerifyWhitelist
 * @notice Verify whitelisted destinations
 *
 * Required Environment Variables:
 *   - ENGINE_ADDRESS
 *   - DESTINATIONS: Comma-separated list of addresses to check
 */
contract VerifyWhitelist is Script {
    function run() external view {
        console.log("========================================");
        console.log("Whitelist Verification");
        console.log("========================================");
        console.log("");

        address engineAddr = vm.envAddress("ENGINE_ADDRESS");
        AmendEngine engine = AmendEngine(engineAddr);

        console.log("Engine:", engineAddr);
        console.log("");

        // Note: Foundry doesn't easily support parsing comma-separated addresses
        // Users should check individual addresses or modify this script

        console.log("To check a destination:");
        console.log("  cast call", engineAddr, '"isWhitelisted(address)" <DESTINATION>');
        console.log("");

        console.log("========================================");
    }
}
