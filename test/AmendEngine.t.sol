// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { AmendVault } from "../src/AmendVault.sol";
import { AmendEngine } from "../src/AmendEngine.sol";
import { IAmendEngine } from "../src/interfaces/IAmendEngine.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Mock USDC for testing
 * @dev Simulates USDC with 6 decimals
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
 * @dev Simulates an external investment destination
 */
contract MockDestination {
    IERC20 public immutable asset;

    constructor(address asset_) {
        asset = IERC20(asset_);
    }

    /// @notice Approve engine to pull funds (simulates cooperative destination)
    function approveEngine(address engine, uint256 amount) external {
        asset.approve(engine, amount);
    }

    /// @notice Simulate generating profit
    function generateProfit(uint256 amount, address usdc) external {
        MockUSDC(usdc).mint(address(this), amount);
    }

    /// @notice Simulate a loss by burning tokens
    function simulateLoss(uint256 amount) external {
        // Transfer to zero address simulates loss (tokens are "gone")
        asset.transfer(address(0xdead), amount);
    }
}

/**
 * @title AmendEngine Test Suite
 * @notice Comprehensive tests for the AMEND Protocol Engine
 */
contract AmendEngineTest is Test {
    // Events to match against
    event WhitelistAdded(address indexed destination);
    event WhitelistRemoved(address indexed destination);
    event FundsDeployed(address indexed destination, uint256 amount);
    event FundsRecalled(address indexed destination, uint256 amount);
    event EmergencyRecall(address indexed destination, uint256 amount);
    event ProfitSettled(uint256 profitAmount);
    event LossSettled(uint256 lossAmount);

    AmendVault vault;
    AmendEngine engine;
    MockUSDC usdc;
    MockDestination destination1;
    MockDestination destination2;

    // Test addresses
    address owner = makeAddr("owner");
    address admin = makeAddr("admin");
    address manager = makeAddr("manager");
    address reporter = makeAddr("reporter");
    address feeRecipient = makeAddr("treasury");
    address user1 = makeAddr("user1");
    address attacker = makeAddr("attacker");

    // Fee: 10% (1000 basis points)
    uint16 constant FEE_BPS = 1000;

    // Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    // ============ Setup ============

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy Vault
        vm.prank(owner);
        vault = new AmendVault(usdc, "AMEND Vault", "avUSDC", owner, feeRecipient, FEE_BPS);

        // Deploy Engine with admin as initial controller
        engine = new AmendEngine(address(vault), admin);

        // Set engine on vault
        vm.prank(owner);
        vault.setEngine(address(engine));

        // Setup roles: grant separate roles
        vm.startPrank(admin);
        engine.grantRole(MANAGER_ROLE, manager);
        engine.grantRole(REPORTER_ROLE, reporter);
        vm.stopPrank();

        // Deploy mock destinations
        destination1 = new MockDestination(address(usdc));
        destination2 = new MockDestination(address(usdc));

        // Whitelist destinations
        vm.startPrank(admin);
        engine.addToWhitelist(address(destination1));
        engine.addToWhitelist(address(destination2));
        vm.stopPrank();

        // Mint USDC to user and deposit to vault
        usdc.mint(user1, 100_000e6);
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(10_000e6, user1);
        vm.stopPrank();
    }

    // ============ Access Control Tests ============

    function test_OnlyAdminCanWhitelist() public {
        address newDest = makeAddr("newDest");

        // Non-admin cannot whitelist
        vm.prank(manager);
        vm.expectRevert();
        engine.addToWhitelist(newDest);

        vm.prank(reporter);
        vm.expectRevert();
        engine.addToWhitelist(newDest);

        vm.prank(attacker);
        vm.expectRevert();
        engine.addToWhitelist(newDest);

        // Admin can whitelist
        vm.prank(admin);
        engine.addToWhitelist(newDest);
        assertTrue(engine.isWhitelisted(newDest));
    }

    function test_OnlyManagerCanDeployFunds() public {
        // Create a fresh reporter without manager role
        address pureReporter = makeAddr("pureReporter");
        vm.prank(admin);
        engine.grantRole(REPORTER_ROLE, pureReporter);

        // Pure reporter cannot deploy
        vm.prank(pureReporter);
        vm.expectRevert();
        engine.deployFunds(address(destination1), 1000e6);

        // Attacker cannot deploy
        vm.prank(attacker);
        vm.expectRevert();
        engine.deployFunds(address(destination1), 1000e6);

        // Manager can deploy
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);
        assertEq(engine.getDeployedTo(address(destination1)), 1000e6);
    }

    function test_OnlyReporterCanSettle() public {
        // Setup: deploy and recall funds to have profit scenario
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        // Simulate profit
        destination1.generateProfit(100e6, address(usdc));
        destination1.approveEngine(address(engine), 1100e6);

        // Recall funds (including profit to engine)
        vm.prank(manager);
        engine.recallFunds(address(destination1), 1000e6);

        // Profit sits in engine, transfer to engine for settlement
        vm.prank(address(destination1));
        usdc.transfer(address(engine), 100e6);

        // Create pure manager without reporter role
        address pureManager = makeAddr("pureManager");
        vm.prank(admin);
        engine.grantRole(MANAGER_ROLE, pureManager);

        // Pure manager cannot settle
        vm.prank(pureManager);
        vm.expectRevert();
        engine.settleProfit(100e6);

        // Attacker cannot settle
        vm.prank(attacker);
        vm.expectRevert();
        engine.settleProfit(100e6);

        // Reporter can settle
        vm.prank(reporter);
        engine.settleProfit(100e6);
    }

    // ============ Whitelist Tests ============

    function test_AddToWhitelist() public {
        address newDest = makeAddr("newDest");

        assertFalse(engine.isWhitelisted(newDest));

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit WhitelistAdded(newDest);
        engine.addToWhitelist(newDest);

        assertTrue(engine.isWhitelisted(newDest));
    }

    function test_RemoveFromWhitelist() public {
        assertTrue(engine.isWhitelisted(address(destination1)));

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit WhitelistRemoved(address(destination1));
        engine.removeFromWhitelist(address(destination1));

        assertFalse(engine.isWhitelisted(address(destination1)));
    }

    function test_CannotDeployToNonWhitelisted() public {
        address notWhitelisted = makeAddr("notWhitelisted");

        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IAmendEngine.NotWhitelisted.selector, notWhitelisted)
        );
        engine.deployFunds(notWhitelisted, 1000e6);
    }

    function test_CannotRemoveWhitelistWithDeployedFunds() public {
        // Deploy funds to destination1
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        // Try to remove from whitelist - should fail
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAmendEngine.CannotRemoveWithDeployedFunds.selector, address(destination1), 1000e6
            )
        );
        engine.removeFromWhitelist(address(destination1));
    }

    function test_CannotWhitelistZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(IAmendEngine.ZeroAddress.selector);
        engine.addToWhitelist(address(0));
    }

    function test_CannotWhitelistTwice() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAmendEngine.AlreadyWhitelisted.selector, address(destination1))
        );
        engine.addToWhitelist(address(destination1));
    }

    // ============ Fund Management Tests ============

    function test_DeployFunds_Success() public {
        uint256 vaultBalanceBefore = usdc.balanceOf(address(vault));
        uint256 destBalanceBefore = usdc.balanceOf(address(destination1));

        vm.prank(manager);
        vm.expectEmit(true, false, false, true);
        emit FundsDeployed(address(destination1), 1000e6);
        engine.deployFunds(address(destination1), 1000e6);

        // Check balances
        assertEq(usdc.balanceOf(address(vault)), vaultBalanceBefore - 1000e6);
        assertEq(usdc.balanceOf(address(destination1)), destBalanceBefore + 1000e6);

        // Check accounting
        assertEq(engine.getDeployedTo(address(destination1)), 1000e6);
        assertEq(engine.getTotalDeployed(), 1000e6);

        // Vault's investedAssets should be updated
        assertEq(vault.investedAssets(), 1000e6);
    }

    function test_DeployFunds_InsufficientBalance() public {
        // Try to deploy more than vault has
        vm.prank(manager);
        vm.expectRevert(); // Vault will revert due to insufficient balance
        engine.deployFunds(address(destination1), 100_000e6);
    }

    function test_DeployFunds_ZeroAmount() public {
        vm.prank(manager);
        vm.expectRevert(IAmendEngine.ZeroAmount.selector);
        engine.deployFunds(address(destination1), 0);
    }

    function test_RecallFunds_Success() public {
        // First deploy
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        // Destination approves engine to pull funds back
        destination1.approveEngine(address(engine), 1000e6);

        uint256 vaultBalanceBefore = usdc.balanceOf(address(vault));

        // Recall
        vm.prank(manager);
        vm.expectEmit(true, false, false, true);
        emit FundsRecalled(address(destination1), 1000e6);
        engine.recallFunds(address(destination1), 1000e6);

        // Check balances
        assertEq(usdc.balanceOf(address(vault)), vaultBalanceBefore + 1000e6);
        assertEq(usdc.balanceOf(address(destination1)), 0);

        // Check accounting
        assertEq(engine.getDeployedTo(address(destination1)), 0);
        assertEq(engine.getTotalDeployed(), 0);

        // Vault's investedAssets should be updated
        assertEq(vault.investedAssets(), 0);
    }

    function test_RecallFunds_ExceedsDeployed() public {
        // Deploy 1000
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        destination1.approveEngine(address(engine), 2000e6);

        // Try to recall 2000 - should fail
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAmendEngine.RecallExceedsDeployed.selector, address(destination1), 2000e6, 1000e6
            )
        );
        engine.recallFunds(address(destination1), 2000e6);
    }

    function test_RecallFunds_ZeroAmount() public {
        vm.prank(manager);
        vm.expectRevert(IAmendEngine.ZeroAmount.selector);
        engine.recallFunds(address(destination1), 0);
    }

    // ============ Settlement Tests ============

    function test_SettleProfit_UpdatesVault() public {
        // Setup: deploy funds
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        // Simulate 10% profit
        destination1.generateProfit(100e6, address(usdc));
        destination1.approveEngine(address(engine), 1100e6);

        // Recall original + profit
        vm.prank(manager);
        engine.recallFunds(address(destination1), 1000e6);

        // Transfer profit from destination to engine
        vm.prank(address(destination1));
        usdc.transfer(address(engine), 100e6);

        uint256 treasurySharesBefore = vault.balanceOf(feeRecipient);

        // Settle profit
        vm.prank(reporter);
        vm.expectEmit(false, false, false, true);
        emit ProfitSettled(100e6);
        engine.settleProfit(100e6);

        // Treasury should have received fee shares
        uint256 treasurySharesAfter = vault.balanceOf(feeRecipient);
        assertGt(treasurySharesAfter, treasurySharesBefore, "Treasury should receive fee shares");
    }

    function test_SettleLoss_UpdatesVault() public {
        // Setup: deploy funds
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        // Simulate 20% loss - destination only has 800 left
        destination1.simulateLoss(200e6);
        destination1.approveEngine(address(engine), 800e6);

        // Recall what's left (this adjusts deployed tracking)
        vm.prank(manager);
        engine.recallFunds(address(destination1), 800e6);

        // Now deployed[destination1] = 200 (the loss amount)
        // We need to manually clear this and report the loss
        // In a real scenario, the accounting would be done differently

        uint256 treasurySharesBefore = vault.balanceOf(feeRecipient);
        uint256 navBefore = vault.totalAssets();

        // Settle loss (200 was lost)
        vm.prank(reporter);
        vm.expectEmit(false, false, false, true);
        emit LossSettled(200e6);
        engine.settleLoss(200e6);

        // Treasury shares should NOT increase (NO FEE ON LOSS)
        uint256 treasurySharesAfter = vault.balanceOf(feeRecipient);
        assertEq(treasurySharesAfter, treasurySharesBefore, "NO FEE ON LOSS");

        // NAV should decrease
        uint256 navAfter = vault.totalAssets();
        assertLt(navAfter, navBefore, "NAV should decrease after loss");
    }

    function test_SettleProfit_NotBacked() public {
        // Engine has no balance, cannot settle profit
        vm.prank(reporter);
        vm.expectRevert(abi.encodeWithSelector(IAmendEngine.ProfitNotBacked.selector, 100e6, 0));
        engine.settleProfit(100e6);
    }

    function test_SettleProfit_ZeroAmount() public {
        vm.prank(reporter);
        vm.expectRevert(IAmendEngine.NothingToSettle.selector);
        engine.settleProfit(0);
    }

    function test_SettleLoss_ZeroAmount() public {
        vm.prank(reporter);
        vm.expectRevert(IAmendEngine.NothingToSettle.selector);
        engine.settleLoss(0);
    }

    // ============ Pause Tests ============

    function test_PauseUnpause() public {
        assertFalse(engine.isPaused());

        vm.prank(admin);
        engine.pause();
        assertTrue(engine.isPaused());

        // Cannot deploy when paused
        vm.prank(manager);
        vm.expectRevert();
        engine.deployFunds(address(destination1), 1000e6);

        // Unpause
        vm.prank(admin);
        engine.unpause();
        assertFalse(engine.isPaused());

        // Can deploy again
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);
    }

    function test_OnlyAdminCanPause() public {
        vm.prank(manager);
        vm.expectRevert();
        engine.pause();

        vm.prank(reporter);
        vm.expectRevert();
        engine.pause();

        vm.prank(admin);
        engine.pause();
        assertTrue(engine.isPaused());
    }

    // ============ Emergency Recall Tests ============

    function test_EmergencyRecall_ByAdmin() public {
        // Deploy funds
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        destination1.approveEngine(address(engine), 1000e6);

        // Admin can emergency recall
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit EmergencyRecall(address(destination1), 1000e6);
        engine.emergencyRecall(address(destination1));

        assertEq(engine.getDeployedTo(address(destination1)), 0);
    }

    function test_EmergencyRecall_ByManager() public {
        // Deploy funds
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        destination1.approveEngine(address(engine), 1000e6);

        // Manager can also emergency recall
        vm.prank(manager);
        engine.emergencyRecall(address(destination1));

        assertEq(engine.getDeployedTo(address(destination1)), 0);
    }

    function test_EmergencyRecall_NotByReporter() public {
        vm.prank(manager);
        engine.deployFunds(address(destination1), 1000e6);

        destination1.approveEngine(address(engine), 1000e6);

        // Reporter cannot emergency recall
        vm.prank(reporter);
        vm.expectRevert();
        engine.emergencyRecall(address(destination1));
    }

    // ============ Integration Tests ============

    function test_FullCycle_VaultToEngineAndBack() public {
        uint256 initialNav = vault.totalAssets();
        uint256 initialUserValue = vault.convertToAssets(vault.balanceOf(user1));

        // 1. Manager deploys 5000 USDC to destination1
        vm.prank(manager);
        engine.deployFunds(address(destination1), 5000e6);

        // NAV should remain unchanged (just location change)
        assertEq(vault.totalAssets(), initialNav, "NAV unchanged after deploy");

        // 2. Destination generates 10% profit
        destination1.generateProfit(500e6, address(usdc));
        destination1.approveEngine(address(engine), 5500e6);

        // 3. Manager recalls original
        vm.prank(manager);
        engine.recallFunds(address(destination1), 5000e6);

        // 4. Transfer profit to engine
        vm.prank(address(destination1));
        usdc.transfer(address(engine), 500e6);

        // 5. Reporter settles profit
        vm.prank(reporter);
        engine.settleProfit(500e6);

        // 6. Verify results
        uint256 finalNav = vault.totalAssets();
        uint256 finalUserValue = vault.convertToAssets(vault.balanceOf(user1));

        assertEq(finalNav, initialNav + 500e6, "NAV increased by profit");
        assertGt(finalUserValue, initialUserValue, "User value increased");
        assertLt(finalUserValue, initialUserValue + 500e6, "User diluted by fee");
        assertGt(vault.balanceOf(feeRecipient), 0, "Treasury received fee shares");

        console.log("Initial User Value:", initialUserValue);
        console.log("Final User Value:", finalUserValue);
        console.log("User Gain:", finalUserValue - initialUserValue);
        console.log("Treasury Shares:", vault.balanceOf(feeRecipient));
    }

    function test_FullCycle_WithLoss() public {
        uint256 initialNav = vault.totalAssets();

        // 1. Deploy
        vm.prank(manager);
        engine.deployFunds(address(destination1), 5000e6);

        // 2. Destination loses 20%
        destination1.simulateLoss(1000e6);
        destination1.approveEngine(address(engine), 4000e6);

        // 3. Recall what's left
        vm.prank(manager);
        engine.recallFunds(address(destination1), 4000e6);

        // 4. Report the loss
        // Note: deployed[destination1] is now 1000 (the unreturned amount)
        // We clear this by adjusting the tracking
        vm.prank(reporter);
        engine.settleLoss(1000e6);

        // 5. Verify: NO FEE ON LOSS
        assertEq(vault.balanceOf(feeRecipient), 0, "ZERO FEE ON LOSS");
        assertEq(vault.totalAssets(), initialNav - 1000e6, "NAV reduced by loss");
    }

    // ============ Fuzz Tests ============

    function testFuzz_DeployRecallAccounting(uint256 amount) public {
        // Bound to reasonable amounts (1 USDC to vault balance)
        amount = bound(amount, 1e6, vault.totalAssets());

        // Deploy
        vm.prank(manager);
        engine.deployFunds(address(destination1), amount);

        assertEq(engine.getDeployedTo(address(destination1)), amount);
        assertEq(engine.getTotalDeployed(), amount);

        // Approve and recall
        destination1.approveEngine(address(engine), amount);

        vm.prank(manager);
        engine.recallFunds(address(destination1), amount);

        assertEq(engine.getDeployedTo(address(destination1)), 0);
        assertEq(engine.getTotalDeployed(), 0);
    }

    function testFuzz_MultipleDestinations(uint256 amount1, uint256 amount2) public {
        // Bound amounts
        uint256 vaultBalance = vault.totalAssets();
        amount1 = bound(amount1, 1e6, vaultBalance / 2);
        amount2 = bound(amount2, 1e6, vaultBalance / 2);

        // Deploy to both destinations
        vm.startPrank(manager);
        engine.deployFunds(address(destination1), amount1);
        engine.deployFunds(address(destination2), amount2);
        vm.stopPrank();

        // Verify accounting
        assertEq(engine.getDeployedTo(address(destination1)), amount1);
        assertEq(engine.getDeployedTo(address(destination2)), amount2);
        assertEq(engine.getTotalDeployed(), amount1 + amount2);

        // Recall from both
        destination1.approveEngine(address(engine), amount1);
        destination2.approveEngine(address(engine), amount2);

        vm.startPrank(manager);
        engine.recallFunds(address(destination1), amount1);
        engine.recallFunds(address(destination2), amount2);
        vm.stopPrank();

        assertEq(engine.getTotalDeployed(), 0);
    }

    // ============ View Function Tests ============

    function test_ViewFunctions() public {
        assertEq(engine.vault(), address(vault));
        assertEq(engine.asset(), address(usdc));
        assertTrue(engine.isWhitelisted(address(destination1)));
        assertFalse(engine.isWhitelisted(makeAddr("random")));
        assertEq(engine.getTotalDeployed(), 0);
        assertEq(engine.getDeployedTo(address(destination1)), 0);
        assertFalse(engine.isPaused());
    }

    // ============ Constructor Tests ============

    function test_ConstructorZeroVault() public {
        vm.expectRevert(IAmendEngine.ZeroAddress.selector);
        new AmendEngine(address(0), admin);
    }

    function test_ConstructorZeroAdmin() public {
        vm.expectRevert(IAmendEngine.ZeroAddress.selector);
        new AmendEngine(address(vault), address(0));
    }

    function test_ConstructorSetsRoles() public {
        AmendEngine newEngine = new AmendEngine(address(vault), admin);

        assertTrue(newEngine.hasRole(newEngine.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(newEngine.hasRole(ADMIN_ROLE, admin));
        assertTrue(newEngine.hasRole(MANAGER_ROLE, admin));
        assertTrue(newEngine.hasRole(REPORTER_ROLE, admin));
    }
}
