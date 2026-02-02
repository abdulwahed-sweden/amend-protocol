// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { AmendVault } from "../src/AmendVault.sol";
import { AmendEngine } from "../src/AmendEngine.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Mock USDC for testing
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/**
 * @title Mock Investment Destination
 * @dev Simulates an external investment destination that can generate yield or loss
 */
contract MockDestination {
    IERC20 public immutable asset;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    function approveEngine(address engine, uint256 amount) external {
        asset.approve(engine, amount);
    }

    function generateProfit(uint256 amount, address usdc) external {
        MockUSDC(usdc).mint(address(this), amount);
    }

    function simulateLoss(uint256 amount) external {
        asset.transfer(address(0xdead), amount);
    }
}

/**
 * @title Integration Test Suite
 * @notice End-to-end tests for the complete AMEND Protocol system
 * @dev Tests the full user journey and system-wide invariants
 */
contract IntegrationTest is Test {
    AmendVault vault;
    AmendEngine engine;
    MockUSDC usdc;
    MockDestination destination;

    // Test addresses
    address owner = makeAddr("owner");
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address reporter = makeAddr("reporter");
    address feeRecipient = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    // Fee: 10%
    uint16 constant FEE_BPS = 1000;

    // Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    // ============ Setup ============

    function setUp() public {
        // Deploy infrastructure
        usdc = new MockUSDC();

        vm.prank(owner);
        vault = new AmendVault(usdc, "AMEND Vault", "avUSDC", owner, feeRecipient, FEE_BPS);

        engine = new AmendEngine(address(vault), admin);

        vm.prank(owner);
        vault.setEngine(address(engine));

        // Setup roles
        vm.startPrank(admin);
        engine.grantRole(MANAGER_ROLE, manager);
        engine.grantRole(REPORTER_ROLE, reporter);
        vm.stopPrank();

        // Deploy and whitelist destination
        destination = new MockDestination(address(usdc));
        vm.prank(admin);
        engine.addToWhitelist(address(destination));

        // Setup users
        usdc.mint(user1, 100_000e6);
        usdc.mint(user2, 200_000e6);
        usdc.mint(user3, 50_000e6);

        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ Complete User Journeys ============

    /**
     * @notice Test: Deposit → Invest → Profit → Withdraw
     * @dev Complete profitable cycle with fee distribution
     */
    function test_CompleteJourney_Profit() public {
        console.log("=== COMPLETE JOURNEY: PROFIT ===");

        // 1. User1 deposits 10,000 USDC
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        uint256 user1SharesInitial = vault.balanceOf(user1);
        uint256 navInitial = vault.totalAssets();
        console.log("Initial NAV:", navInitial);
        console.log("User1 shares:", user1SharesInitial);

        // 2. Manager deploys 8,000 USDC (80% utilization)
        vm.prank(manager);
        engine.deployFunds(address(destination), 8_000e6);

        assertEq(vault.investedAssets(), 8_000e6, "Invested assets tracked");
        assertEq(vault.totalAssets(), navInitial, "NAV unchanged after deploy");

        // 3. Destination generates 10% profit (800 USDC)
        destination.generateProfit(800e6, address(usdc));
        destination.approveEngine(address(engine), 8_800e6);

        // 4. Manager recalls original + profit stays at destination
        vm.prank(manager);
        engine.recallFunds(address(destination), 8_000e6);

        // Transfer profit to engine
        vm.prank(address(destination));
        usdc.transfer(address(engine), 800e6);

        // 5. Reporter settles profit
        vm.prank(reporter);
        engine.settleProfit(800e6);

        // 6. Verify results
        uint256 navFinal = vault.totalAssets();
        uint256 treasuryShares = vault.balanceOf(feeRecipient);
        uint256 user1ValueFinal = vault.convertToAssets(vault.balanceOf(user1));

        console.log("Final NAV:", navFinal);
        console.log("Treasury shares:", treasuryShares);
        console.log("User1 final value:", user1ValueFinal);

        assertEq(navFinal, navInitial + 800e6, "NAV increased by profit");
        assertGt(treasuryShares, 0, "Treasury received fee shares");
        assertGt(user1ValueFinal, 10_000e6, "User1 gained value");
        assertLt(user1ValueFinal, 10_800e6, "User1 diluted by fee");

        // 7. User1 withdraws everything
        uint256 user1Shares = vault.balanceOf(user1);
        vm.startPrank(user1);
        vault.redeem(user1Shares, user1, user1);
        vm.stopPrank();

        console.log("User1 withdrawn USDC:", usdc.balanceOf(user1));
        assertGt(usdc.balanceOf(user1), 100_000e6, "User1 gained USDC");
    }

    /**
     * @notice Test: Deposit → Invest → Loss → Withdraw
     * @dev Complete loss cycle with NO FEE
     */
    function test_CompleteJourney_Loss() public {
        console.log("=== COMPLETE JOURNEY: LOSS ===");

        // 1. User1 deposits 10,000 USDC
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        uint256 navInitial = vault.totalAssets();

        // 2. Manager deploys 8,000 USDC
        vm.prank(manager);
        engine.deployFunds(address(destination), 8_000e6);

        // 3. Destination loses 25% (2,000 USDC)
        destination.simulateLoss(2_000e6);
        destination.approveEngine(address(engine), 6_000e6);

        // 4. Manager recalls what's left
        vm.prank(manager);
        engine.recallFunds(address(destination), 6_000e6);

        // Now deployed tracking shows 2000 still "deployed" (the loss)
        // We need to account for this in the loss report

        // 5. Reporter settles loss
        vm.prank(reporter);
        engine.settleLoss(2_000e6);

        // 6. Verify NO FEE ON LOSS
        uint256 treasuryShares = vault.balanceOf(feeRecipient);
        uint256 navFinal = vault.totalAssets();
        uint256 user1ValueFinal = vault.convertToAssets(vault.balanceOf(user1));

        console.log("Final NAV:", navFinal);
        console.log("Treasury shares:", treasuryShares);
        console.log("User1 final value:", user1ValueFinal);

        assertEq(treasuryShares, 0, "ZERO FEE ON LOSS");
        assertEq(navFinal, navInitial - 2_000e6, "NAV decreased by loss");
        assertEq(user1ValueFinal, 8_000e6, "User bears loss proportionally");

        // 7. User1 withdraws
        uint256 user1Shares = vault.balanceOf(user1);
        vm.startPrank(user1);
        vault.redeem(user1Shares, user1, user1);
        vm.stopPrank();

        assertEq(usdc.balanceOf(user1), 98_000e6, "User1 has 98k USDC (lost 2k)");
    }

    /**
     * @notice Test: Multi-user scenario with profit sharing
     */
    function test_MultiUser_ProfitSharing() public {
        console.log("=== MULTI-USER PROFIT SHARING ===");

        // Users deposit different amounts
        vm.prank(user1);
        vault.deposit(10_000e6, user1); // 10k

        vm.prank(user2);
        vault.deposit(30_000e6, user2); // 30k

        vm.prank(user3);
        vault.deposit(10_000e6, user3); // 10k

        // Total: 50k USDC, User2 has 60% of shares
        uint256 totalShares = vault.totalSupply();
        assertEq(vault.balanceOf(user1) * 100 / totalShares, 20, "User1 has 20%");
        assertEq(vault.balanceOf(user2) * 100 / totalShares, 60, "User2 has 60%");
        assertEq(vault.balanceOf(user3) * 100 / totalShares, 20, "User3 has 20%");

        // Deploy all and generate 10% profit
        vm.prank(manager);
        engine.deployFunds(address(destination), 50_000e6);

        destination.generateProfit(5_000e6, address(usdc));
        destination.approveEngine(address(engine), 55_000e6);

        vm.prank(manager);
        engine.recallFunds(address(destination), 50_000e6);

        vm.prank(address(destination));
        usdc.transfer(address(engine), 5_000e6);

        vm.prank(reporter);
        engine.settleProfit(5_000e6);

        // Verify proportional distribution
        uint256 user1Value = vault.convertToAssets(vault.balanceOf(user1));
        uint256 user2Value = vault.convertToAssets(vault.balanceOf(user2));
        uint256 user3Value = vault.convertToAssets(vault.balanceOf(user3));

        console.log("User1 value:", user1Value);
        console.log("User2 value:", user2Value);
        console.log("User3 value:", user3Value);

        // User2 should have 3x User1's value
        assertApproxEqRel(user2Value, user1Value * 3, 0.01e18, "3:1 ratio maintained");
        assertApproxEqRel(user1Value, user3Value, 0.01e18, "User1 and User3 equal");

        // All users gained
        assertGt(user1Value, 10_000e6, "User1 gained");
        assertGt(user2Value, 30_000e6, "User2 gained");
        assertGt(user3Value, 10_000e6, "User3 gained");
    }

    /**
     * @notice Test: Multi-user scenario with loss sharing (NO FEE)
     */
    function test_MultiUser_LossSharing() public {
        console.log("=== MULTI-USER LOSS SHARING ===");

        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        vm.prank(user2);
        vault.deposit(40_000e6, user2);

        uint256 totalShares = vault.totalSupply();

        // Deploy and simulate 20% loss
        vm.prank(manager);
        engine.deployFunds(address(destination), 50_000e6);

        destination.simulateLoss(10_000e6);
        destination.approveEngine(address(engine), 40_000e6);

        vm.prank(manager);
        engine.recallFunds(address(destination), 40_000e6);

        vm.prank(reporter);
        engine.settleLoss(10_000e6);

        // Verify NO FEE and proportional loss
        assertEq(vault.balanceOf(feeRecipient), 0, "ZERO FEE ON LOSS");

        uint256 user1Value = vault.convertToAssets(vault.balanceOf(user1));
        uint256 user2Value = vault.convertToAssets(vault.balanceOf(user2));

        console.log("User1 value after loss:", user1Value);
        console.log("User2 value after loss:", user2Value);

        // Both users should have lost 20%
        assertApproxEqRel(user1Value, 8_000e6, 0.01e18, "User1 lost 20%");
        assertApproxEqRel(user2Value, 32_000e6, 0.01e18, "User2 lost 20%");
    }

    // ============ Edge Case Tests ============

    function test_EdgeCase_MaxDeposit() public {
        // Test with very large deposit
        uint256 maxAmount = 1_000_000_000e6; // 1 billion USDC
        usdc.mint(user1, maxAmount);

        vm.startPrank(user1);
        usdc.approve(address(vault), maxAmount);
        vault.deposit(maxAmount, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), maxAmount);

        // Deploy, profit, recall
        vm.prank(manager);
        engine.deployFunds(address(destination), maxAmount / 2);

        destination.generateProfit(maxAmount / 10, address(usdc));
        destination.approveEngine(address(engine), type(uint256).max);

        vm.prank(manager);
        engine.recallFunds(address(destination), maxAmount / 2);

        vm.prank(address(destination));
        usdc.transfer(address(engine), maxAmount / 10);

        vm.prank(reporter);
        engine.settleProfit(maxAmount / 10);

        assertGt(vault.totalAssets(), maxAmount, "NAV increased");
    }

    function test_EdgeCase_SmallAmounts() public {
        // Test with minimum viable amounts (1 USDC)
        usdc.mint(user1, 1e6);

        vm.startPrank(user1);
        usdc.approve(address(vault), 1e6);
        vault.deposit(1e6, user1);
        vm.stopPrank();

        assertEq(vault.totalAssets(), 1e6);
    }

    function test_EdgeCase_MultipleInvestmentCycles() public {
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        for (uint256 i = 0; i < 5; i++) {
            // Deploy
            vm.prank(manager);
            engine.deployFunds(address(destination), 1_000e6);

            // Generate small profit
            destination.generateProfit(100e6, address(usdc));
            destination.approveEngine(address(engine), 1_100e6);

            // Recall
            vm.prank(manager);
            engine.recallFunds(address(destination), 1_000e6);

            vm.prank(address(destination));
            usdc.transfer(address(engine), 100e6);

            vm.prank(reporter);
            engine.settleProfit(100e6);
        }

        // Should have compounded profits (5 cycles * 100 USDC = 500 USDC profit)
        assertGe(vault.totalAssets(), 10_500e6, "Profits accumulated");
    }

    // ============ Invariant Tests ============

    /**
     * @notice Invariant: Vault assets must match reality
     */
    function invariant_VaultAssetsMatchReality() public view {
        uint256 onChainBalance = usdc.balanceOf(address(vault));
        uint256 investedAssets = vault.investedAssets();
        uint256 totalAssets = vault.totalAssets();

        assertEq(totalAssets, onChainBalance + investedAssets, "NAV = balance + invested");
    }

    /**
     * @notice Invariant: Engine accounting must be consistent
     */
    function test_Invariant_EngineAccountingConsistent() public {
        vm.prank(user1);
        vault.deposit(50_000e6, user1);

        // Deploy to multiple destinations
        MockDestination dest2 = new MockDestination(address(usdc));
        vm.prank(admin);
        engine.addToWhitelist(address(dest2));

        vm.startPrank(manager);
        engine.deployFunds(address(destination), 20_000e6);
        engine.deployFunds(address(dest2), 15_000e6);
        vm.stopPrank();

        // Verify totalDeployed = sum of deployed
        uint256 deployed1 = engine.getDeployedTo(address(destination));
        uint256 deployed2 = engine.getDeployedTo(address(dest2));
        uint256 totalDeployed = engine.getTotalDeployed();

        assertEq(totalDeployed, deployed1 + deployed2, "Accounting invariant");
    }

    /**
     * @notice Invariant: Engine cannot create money
     */
    function test_Invariant_EngineCannotCreateMoney() public {
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        uint256 systemValueBefore = usdc.balanceOf(address(vault)) + usdc.balanceOf(address(engine))
            + usdc.balanceOf(address(destination));

        // Deploy funds
        vm.prank(manager);
        engine.deployFunds(address(destination), 5_000e6);

        uint256 systemValueAfter = usdc.balanceOf(address(vault)) + usdc.balanceOf(address(engine))
            + usdc.balanceOf(address(destination));

        assertEq(systemValueAfter, systemValueBefore, "No money created during deploy");
    }

    /**
     * @notice CORE INVARIANT: No fee on loss
     */
    function test_Invariant_NoFeeOnLoss() public {
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        uint256 treasuryBefore = vault.balanceOf(feeRecipient);

        // Deploy and lose funds
        vm.prank(manager);
        engine.deployFunds(address(destination), 8_000e6);

        destination.simulateLoss(4_000e6);
        destination.approveEngine(address(engine), 4_000e6);

        vm.prank(manager);
        engine.recallFunds(address(destination), 4_000e6);

        vm.prank(reporter);
        engine.settleLoss(4_000e6);

        uint256 treasuryAfter = vault.balanceOf(feeRecipient);

        assertEq(treasuryAfter, treasuryBefore, "NO FEE ON LOSS - Core Invariant");
    }

    /**
     * @notice Test late joiner doesn't get unfair advantage
     */
    function test_LateJoiner_NoUnfairAdvantage() public {
        // User1 deposits first
        vm.prank(user1);
        vault.deposit(10_000e6, user1);

        // Generate profit
        vm.prank(manager);
        engine.deployFunds(address(destination), 10_000e6);

        destination.generateProfit(1_000e6, address(usdc));
        destination.approveEngine(address(engine), 11_000e6);

        vm.prank(manager);
        engine.recallFunds(address(destination), 10_000e6);

        vm.prank(address(destination));
        usdc.transfer(address(engine), 1_000e6);

        vm.prank(reporter);
        engine.settleProfit(1_000e6);

        // User2 joins AFTER profit
        uint256 user2DepositAmount = 10_000e6;
        vm.prank(user2);
        vault.deposit(user2DepositAmount, user2);

        // User2's shares should be worth less than User1's initial deposit
        // because share price has increased
        uint256 user2Shares = vault.balanceOf(user2);
        uint256 user1Shares = vault.balanceOf(user1);

        console.log("User1 shares:", user1Shares);
        console.log("User2 shares:", user2Shares);

        // User2 should have fewer shares for same deposit
        assertLt(user2Shares, user1Shares, "Late joiner gets fewer shares");

        // But both should have same value per share now
        uint256 user1Value = vault.convertToAssets(user1Shares);
        uint256 user2Value = vault.convertToAssets(user2Shares);

        console.log("User1 value:", user1Value);
        console.log("User2 value:", user2Value);

        // User1 should have gained, User2 just joined at fair price
        assertGt(user1Value, 10_000e6, "User1 gained from profit");
        assertApproxEqRel(user2Value, user2DepositAmount, 0.01e18, "User2 at fair value");
    }

    /**
     * @notice Test system handles dust amounts correctly
     */
    function test_DustAmounts() public {
        // Deposit with some "dust"
        uint256 dustAmount = 1; // 1 wei of USDC
        usdc.mint(user1, dustAmount);

        vm.startPrank(user1);
        usdc.approve(address(vault), dustAmount);
        vault.deposit(dustAmount, user1);
        vm.stopPrank();

        // Should work without reverting
        assertTrue(vault.balanceOf(user1) > 0 || dustAmount == 0, "Dust handled");
    }
}
