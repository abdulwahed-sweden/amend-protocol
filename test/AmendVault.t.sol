// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { AmendVault } from "../src/AmendVault.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Mock USDC for testing
 * @dev Simulates USDC with 6 decimals (like real USDC on Base)
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6; // Base USDC uses 6 decimals
    }
}

/**
 * @title AMEND Vault Test Suite
 * @notice Comprehensive tests for the AMEND protocol
 * @dev Tests the core invariant: NO FEE ON LOSS
 */
contract AmendVaultTest is Test {
    AmendVault vault;
    MockUSDC usdc;

    // Test addresses
    address owner = makeAddr("owner");
    address engine = makeAddr("engine");
    address feeRecipient = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    // Fee: 10% (1000 basis points)
    uint16 constant FEE_BPS = 1000;

    // ============ Setup ============

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy AMEND Vault
        vault = new AmendVault(usdc, "AMEND Vault", "avUSDC", owner, feeRecipient, FEE_BPS);

        // Set engine
        vault.setEngine(engine);
        vm.stopPrank();

        // Mint initial USDC to test users
        usdc.mint(user1, 100_000e6); // 100k USDC
        usdc.mint(user2, 100_000e6);

        // Users approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ Scenario 1: Basic Deposit & Invest ============

    function test_DepositAndInvest() public {
        uint256 depositAmt = 1000e6; // 1000 USDC

        // User deposits
        vm.prank(user1);
        vault.deposit(depositAmt, user1);

        // Verify initial state
        assertEq(vault.totalAssets(), depositAmt, "Total assets should equal deposit");
        assertEq(vault.balanceOf(user1), depositAmt, "Shares should be 1:1 initially");

        // Engine invests 50%
        uint256 investAmt = 500e6;
        vm.prank(engine);
        vault.invest(investAmt);

        // Verify post-invest state
        assertEq(usdc.balanceOf(address(vault)), depositAmt - investAmt, "On-chain balance reduced");
        assertEq(vault.investedAssets(), investAmt, "Invested assets tracked");
        assertEq(vault.totalAssets(), depositAmt, "NAV unchanged after invest");
    }

    // ============ Scenario 2: Profit & Fee Collection ============

    function test_ReportProfit_TakesFee() public {
        // 1. User deposits 1000 USDC
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // 2. Engine invests all
        vm.prank(engine);
        vault.invest(1000e6);

        // 3. Simulate profit: Engine earned 100 USDC (10% return)
        usdc.mint(engine, 100e6); // Mint profit to engine

        vm.startPrank(engine);
        usdc.approve(address(vault), 1100e6);

        // Return original capital
        vault.divest(1000e6);

        // Transfer profit to vault
        usdc.transfer(address(vault), 100e6);

        // Report profit (triggers fee calculation)
        vault.reportProfit(100e6);
        vm.stopPrank();

        // ====== Verify Results ======

        // Total assets should be 1100 USDC
        assertEq(vault.totalAssets(), 1100e6, "Total assets = 1100");

        // Treasury should have received fee shares
        uint256 treasuryShares = vault.balanceOf(feeRecipient);
        assertGt(treasuryShares, 0, "Treasury must have shares");

        // User gained value but less than full profit (due to fee dilution)
        uint256 userAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGt(userAssets, 1000e6, "User gained value");
        assertLt(userAssets, 1100e6, "User diluted by fee");

        // Log for visibility
        emit log_named_uint("User final value (USDC)", userAssets);
        emit log_named_uint("Treasury shares", treasuryShares);
    }

    // ============ Scenario 3: Loss & NO Fee (CORE INVARIANT) ============

    function test_ReportLoss_NoFee() public {
        // 1. User deposits 1000 USDC
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // 2. Engine invests all
        vm.prank(engine);
        vault.invest(1000e6);

        // 3. Simulate loss: Engine lost 200, returns only 800
        vm.startPrank(engine);
        usdc.approve(address(vault), 800e6);
        vault.divest(800e6);

        // ✅ FIX: Assert investedAssets before reportLoss
        assertEq(vault.investedAssets(), 200e6, "Invested should be 200 before loss report");

        // Report the loss
        vault.reportLoss(200e6);
        vm.stopPrank();

        // ====== CORE INVARIANT CHECK ======

        assertEq(vault.totalAssets(), 800e6, "NAV dropped to 800");
        assertEq(vault.balanceOf(feeRecipient), 0, "ZERO FEE ON LOSS");
        assertEq(vault.investedAssets(), 0, "Invested assets cleared");

        // User's share value reflects loss
        uint256 userAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertEq(userAssets, 800e6, "User bears loss proportionally");
    }

    // ============ Scenario 4: Loss After Profit (Complex) ============

    function test_LossAfterProfit_NoExtraFees() public {
        // 1. Deposit
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // 2. First cycle: PROFIT
        vm.prank(engine);
        vault.invest(1000e6);

        usdc.mint(engine, 100e6); // Engine earned 100 profit
        vm.startPrank(engine);
        usdc.approve(address(vault), 1100e6);
        vault.divest(1000e6); // Return original
        usdc.transfer(address(vault), 100e6); // Transfer profit
        vault.reportProfit(100e6);
        vm.stopPrank();

        uint256 treasurySharesAfterProfit = vault.balanceOf(feeRecipient);
        assertGt(treasurySharesAfterProfit, 0, "Treasury has shares from profit");

        emit log_named_uint("Treasury shares after profit", treasurySharesAfterProfit);

        // 3. Second cycle: LOSS
        uint256 currentAssets = vault.totalAssets(); // Should be 1100
        vm.prank(engine);
        vault.invest(currentAssets);

        // Engine loses 200, returns only 900
        vm.startPrank(engine);
        usdc.approve(address(vault), 900e6);
        vault.divest(900e6);

        // ✅ Verify investedAssets before loss report
        assertEq(vault.investedAssets(), 200e6, "Should have 200 still invested");

        vault.reportLoss(200e6);
        vm.stopPrank();

        // ====== KEY CHECK: Treasury shares UNCHANGED after loss ======
        uint256 treasurySharesAfterLoss = vault.balanceOf(feeRecipient);
        assertEq(
            treasurySharesAfterLoss,
            treasurySharesAfterProfit,
            "NO EXTRA FEE ON LOSS - Treasury unchanged"
        );

        emit log_named_uint("Treasury shares after loss", treasurySharesAfterLoss);
        emit log_named_uint("Final NAV", vault.totalAssets());
    }

    // ============ Scenario 5: Multiple Users Fairness ============

    function test_MultipleUsers_FairDistribution() public {
        // User1 deposits 1000, User2 deposits 2000
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(user2);
        vault.deposit(2000e6, user2);

        // Engine invests and makes 300 profit (10%)
        vm.prank(engine);
        vault.invest(3000e6);

        usdc.mint(engine, 300e6);
        vm.startPrank(engine);
        usdc.approve(address(vault), 3300e6);
        vault.divest(3000e6);
        usdc.transfer(address(vault), 300e6);
        vault.reportProfit(300e6);
        vm.stopPrank();

        // Check proportional distribution
        uint256 user1Value = vault.convertToAssets(vault.balanceOf(user1));
        uint256 user2Value = vault.convertToAssets(vault.balanceOf(user2));

        // User2 should have ~2x User1's value (they deposited 2x)
        assertApproxEqRel(user2Value, user1Value * 2, 0.01e18, "2:1 ratio maintained");
    }

    // ============ Fuzz Tests ============

    function testFuzz_ProfitAlwaysDilutesCorrectly(uint256 depositAmount, uint256 profitAmount)
        public
    {
        // Bound inputs to realistic ranges
        depositAmount = bound(depositAmount, 100e6, 1_000_000_000e6);
        profitAmount = bound(profitAmount, 1e6, depositAmount);

        // Setup: mint and deposit
        usdc.mint(user1, depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Simulate profit (direct transfer for speed)
        usdc.mint(address(vault), profitAmount);

        vm.prank(engine);
        vault.reportProfit(profitAmount);

        // ====== Invariant Check ======
        uint256 userValue = vault.convertToAssets(vault.balanceOf(user1));

        // User must gain but less than full profit (fee taken)
        assertGt(userValue, depositAmount, "User must gain");
        assertLt(userValue, depositAmount + profitAmount, "Fee must be taken");
    }

    function testFuzz_LossNeverTakesFee(uint256 depositAmount, uint256 lossPercentage) public {
        // Bound inputs
        depositAmount = bound(depositAmount, 100e6, 1_000_000_000e6);
        lossPercentage = bound(lossPercentage, 1, 99); // 1% to 99% loss

        uint256 lossAmount = (depositAmount * lossPercentage) / 100;

        // Setup
        usdc.mint(user1, depositAmount);
        vm.prank(user1);
        vault.deposit(depositAmount, user1);

        // Engine invests all
        vm.prank(engine);
        vault.invest(depositAmount);

        // Engine returns partial (simulating loss)
        uint256 returnAmount = depositAmount - lossAmount;
        vm.startPrank(engine);
        usdc.approve(address(vault), returnAmount);
        vault.divest(returnAmount);

        // ✅ Verify investedAssets equals expected loss
        assertEq(vault.investedAssets(), lossAmount, "InvestedAssets should equal loss");

        // Report loss
        vault.reportLoss(lossAmount);
        vm.stopPrank();

        // ====== CORE INVARIANT ======
        assertEq(vault.balanceOf(feeRecipient), 0, "ZERO FEE ON ANY LOSS");
        assertEq(vault.investedAssets(), 0, "Invested assets cleared");
    }

    // ============ Access Control Tests ============

    function test_OnlyEngineCanInvest() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(user1);
        vm.expectRevert("AMEND: not engine");
        vault.invest(500e6);
    }

    function test_OnlyEngineCanReportProfit() public {
        vm.prank(user1);
        vm.expectRevert("AMEND: not engine");
        vault.reportProfit(100e6);
    }

    function test_OnlyOwnerCanSetEngine() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setEngine(user1);
    }

    // ============ Edge Cases ============

    function test_ZeroDepositReverts() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.deposit(0, user1);
    }

    function test_FullWithdrawal() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        uint256 shares = vault.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        assertEq(vault.balanceOf(user1), 0, "All shares redeemed");
        assertEq(usdc.balanceOf(user1), 100_000e6, "USDC returned");
    }

    // ✅ NEW: Test loss cannot exceed invested
    function test_LossCannotExceedInvested() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(500e6); // Only invest 500

        // Try to report 600 loss (more than invested)
        vm.prank(engine);
        vm.expectRevert("AMEND: loss > invested");
        vault.reportLoss(600e6);
    }

    // ✅ NEW: Test profit must be backed by assets
    function test_ProfitMustBeBackedByAssets() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6); // Invest all, vault is empty

        // Try to report profit without returning assets
        vm.prank(engine);
        vm.expectRevert("AMEND: profit not backed by assets");
        vault.reportProfit(100e6);
    }

    // ✅ NEW: Test multiple profit/loss cycles
    function test_MultipleCycles_Fairness() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // Cycle 1: 10% Profit
        vm.prank(engine);
        vault.invest(1000e6);
        usdc.mint(engine, 100e6);
        vm.startPrank(engine);
        usdc.approve(address(vault), 1100e6);
        vault.divest(1000e6);
        usdc.transfer(address(vault), 100e6);
        vault.reportProfit(100e6);
        vm.stopPrank();

        uint256 nav1 = vault.totalAssets();
        uint256 treasury1 = vault.balanceOf(feeRecipient);
        emit log_named_uint("After Cycle 1 (Profit) - NAV", nav1);

        // Cycle 2: 5% Loss
        vm.prank(engine);
        vault.invest(nav1);
        uint256 lossAmount = (nav1 * 5) / 100;
        uint256 returnAmount = nav1 - lossAmount;
        vm.startPrank(engine);
        usdc.approve(address(vault), returnAmount);
        vault.divest(returnAmount);
        vault.reportLoss(lossAmount);
        vm.stopPrank();

        uint256 nav2 = vault.totalAssets();
        uint256 treasury2 = vault.balanceOf(feeRecipient);
        emit log_named_uint("After Cycle 2 (Loss) - NAV", nav2);

        // Cycle 3: 15% Profit
        vm.prank(engine);
        vault.invest(nav2);
        uint256 profitAmount = (nav2 * 15) / 100;
        usdc.mint(engine, profitAmount);
        vm.startPrank(engine);
        usdc.approve(address(vault), nav2 + profitAmount);
        vault.divest(nav2);
        usdc.transfer(address(vault), profitAmount);
        vault.reportProfit(profitAmount);
        vm.stopPrank();

        uint256 treasury3 = vault.balanceOf(feeRecipient);

        // ====== Assertions ======
        // Treasury grew only during profit cycles
        assertEq(treasury2, treasury1, "No fee during loss cycle");
        assertGt(treasury3, treasury2, "Fee taken during profit cycle");

        // User value tracked correctly
        uint256 userFinalValue = vault.convertToAssets(vault.balanceOf(user1));
        assertGt(userFinalValue, 1000e6, "User should be net positive");

        emit log_named_uint("User final value", userFinalValue);
        emit log_named_uint("Treasury final shares", treasury3);
    }
}
