// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AmendVaultV2} from "../../src/v2/AmendVaultV2.sol";
import {AmendEngineV2} from "../../src/v2/AmendEngineV2.sol";

/// @notice Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @notice Mock destination that can simulate trades
contract MockDestination {
    IERC20 public immutable asset;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function approveEngine(address engine, uint256 amount) external {
        asset.approve(engine, amount);
    }

    function simulateProfit(uint256 amount) external {
        // Mint profit (simulating trade gains)
        MockUSDC(address(asset)).mint(address(this), amount);
    }
}

/**
 * @title IntegrationV2Test
 * @author Abdulwahed Mansour
 * @notice Integration tests for AMEND Protocol v2
 */
contract IntegrationV2Test is Test {
    AmendVaultV2 public vault;
    AmendEngineV2 public engine;
    MockUSDC public usdc;
    MockDestination public destination;

    address public admin = address(0x1);
    address public feeRecipient = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public user3 = address(0x5);

    uint16 public constant FEE_BPS = 1000; // 10%

    function setUp() public {
        usdc = new MockUSDC();

        // Deploy vault
        vm.prank(admin);
        vault = new AmendVaultV2(
            IERC20(address(usdc)),
            "AMEND Vault V2",
            "avUSDC",
            admin,
            feeRecipient,
            FEE_BPS
        );

        // Deploy engine
        vm.prank(admin);
        engine = new AmendEngineV2(address(vault), admin);

        // Link vault to engine
        vm.prank(admin);
        vault.setEngine(address(engine));

        // Deploy mock destination
        destination = new MockDestination(address(usdc));

        // Whitelist destination
        vm.prank(admin);
        engine.addToWhitelist(address(destination));

        // Fund users
        usdc.mint(user1, 10_000e6);
        usdc.mint(user2, 20_000e6);
        usdc.mint(user3, 5_000e6);

        // Approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ Full Cycle Tests ============

    function test_FullCycle_DepositInvestProfitWithdraw() public {
        // 1. User deposits
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        assertEq(vault.totalAssets(), 1000e6);
        uint256 userShares = vault.balanceOf(user1);

        // 2. Admin deploys to destination
        vm.prank(admin);
        engine.deployFunds(address(destination), 1000e6);

        assertEq(vault.investedAssets(), 1000e6);
        assertEq(usdc.balanceOf(address(destination)), 1000e6);

        // 3. Destination generates profit
        destination.simulateProfit(100e6);
        destination.approveEngine(address(engine), 1100e6);

        // 4. Admin recalls funds
        vm.prank(admin);
        engine.recallFunds(address(destination), 1000e6);

        // Get the extra 100 profit manually
        usdc.mint(address(engine), 100e6);

        // 5. Admin finalizes trade with profit
        vm.prank(admin);
        engine.finalizeTrade(1000e6, 100e6);

        // Verify: Vault has principal + profit
        assertEq(usdc.balanceOf(address(vault)), 1100e6);
        assertEq(vault.investedAssets(), 0);

        // 6. Fee recipient got shares
        assertGt(vault.balanceOf(feeRecipient), 0);

        // 7. User withdraws (should get more than deposited due to profit minus fees)
        vm.prank(user1);
        uint256 withdrawn = vault.redeem(userShares, user1, user1);

        // User should get ~1090 (1100 - 10% of 100 = 1090)
        assertGt(withdrawn, 1080e6);
        assertLt(withdrawn, 1100e6);
    }

    function test_FullCycle_DepositInvestLossWithdraw() public {
        // 1. User deposits
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        uint256 userShares = vault.balanceOf(user1);
        uint256 feeSharesBefore = vault.balanceOf(feeRecipient);

        // 2. Admin deploys to destination
        vm.prank(admin);
        engine.deployFunds(address(destination), 1000e6);

        // 3. Loss occurs (destination loses 200)
        // Only 800 remains at destination
        destination.approveEngine(address(engine), 800e6);

        // 4. Admin recalls remaining funds
        vm.prank(admin);
        engine.recallFunds(address(destination), 800e6);

        // Note: We recalled 1000 deployed but accounting only got 800 back
        // The 200 difference needs to be reported as loss

        // But wait - recallFunds already reduced _deployed by 800, and original was 1000
        // So we still have 200 "deployed" that's actually lost

        // 5. Report loss
        vm.prank(admin);
        engine.reportLoss(200e6);

        // CORE INVARIANT: NO FEE ON LOSS
        assertEq(vault.balanceOf(feeRecipient), feeSharesBefore);

        // 6. Finalize with remaining principal (no profit)
        vm.prank(admin);
        engine.finalizeTrade(800e6, 0);

        // 7. User withdraws (should get less due to loss)
        vm.prank(user1);
        uint256 withdrawn = vault.redeem(userShares, user1, user1);

        // User should get ~800 (1000 - 200 loss)
        assertEq(withdrawn, 800e6);
    }

    function test_FullCycle_MultipleUsers() public {
        // Users deposit different amounts
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(user2);
        vault.deposit(2000e6, user2);

        vm.prank(user3);
        vault.deposit(500e6, user3);

        uint256 shares1 = vault.balanceOf(user1);
        uint256 shares2 = vault.balanceOf(user2);
        uint256 shares3 = vault.balanceOf(user3);

        assertEq(vault.totalAssets(), 3500e6);

        // Deploy all
        vm.prank(admin);
        engine.deployFunds(address(destination), 3500e6);

        // Simulate profit
        destination.simulateProfit(350e6); // 10% profit
        destination.approveEngine(address(engine), 3850e6);

        vm.prank(admin);
        engine.recallFunds(address(destination), 3500e6);
        usdc.mint(address(engine), 350e6);

        vm.prank(admin);
        engine.finalizeTrade(3500e6, 350e6);

        // Each user withdraws proportionally
        vm.prank(user1);
        uint256 w1 = vault.redeem(shares1, user1, user1);

        vm.prank(user2);
        uint256 w2 = vault.redeem(shares2, user2, user2);

        vm.prank(user3);
        uint256 w3 = vault.redeem(shares3, user3, user3);

        // All users should profit proportionally (minus fees)
        assertGt(w1, 1000e6);
        assertGt(w2, 2000e6);
        assertGt(w3, 500e6);

        // Ratio should be maintained (approximately)
        // w1:w2:w3 ≈ 1:2:0.5
        assertApproxEqRel(w2, w1 * 2, 0.01e18); // 1% tolerance
        assertApproxEqRel(w3 * 2, w1, 0.01e18);
    }

    function test_FullCycle_MultipleCycles() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // Cycle 1: Profit
        vm.prank(admin);
        engine.deployFunds(address(destination), 1000e6);

        destination.simulateProfit(100e6);
        destination.approveEngine(address(engine), 1100e6);

        vm.prank(admin);
        engine.recallFunds(address(destination), 1000e6);
        usdc.mint(address(engine), 100e6);

        vm.prank(admin);
        engine.finalizeTrade(1000e6, 100e6);

        uint256 afterCycle1 = vault.totalAssets();
        assertGt(afterCycle1, 1000e6);

        // Cycle 2: Loss
        vm.prank(admin);
        engine.deployFunds(address(destination), afterCycle1);

        // Lose 10%
        uint256 lossAmount = afterCycle1 / 10;
        destination.approveEngine(address(engine), afterCycle1 - lossAmount);

        vm.prank(admin);
        engine.recallFunds(address(destination), afterCycle1 - lossAmount);

        vm.prank(admin);
        engine.reportLoss(lossAmount);

        vm.prank(admin);
        engine.finalizeTrade(afterCycle1 - lossAmount, 0);

        uint256 afterCycle2 = vault.totalAssets();
        assertLt(afterCycle2, afterCycle1);

        // Cycle 3: Profit again
        vm.prank(admin);
        engine.deployFunds(address(destination), afterCycle2);

        destination.simulateProfit(200e6);
        destination.approveEngine(address(engine), afterCycle2 + 200e6);

        vm.prank(admin);
        engine.recallFunds(address(destination), afterCycle2);
        usdc.mint(address(engine), 200e6);

        vm.prank(admin);
        engine.finalizeTrade(afterCycle2, 200e6);

        uint256 afterCycle3 = vault.totalAssets();
        assertGt(afterCycle3, afterCycle2);
    }

    function test_Emergency_PauseBlocksOperations() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // Pause engine
        vm.prank(admin);
        engine.pause();

        // Deploy should fail
        vm.prank(admin);
        vm.expectRevert();
        engine.deployFunds(address(destination), 500e6);

        // Report loss should fail
        vm.prank(admin);
        vm.expectRevert();
        engine.reportLoss(100e6);

        // Finalize trade should fail
        usdc.mint(address(engine), 500e6);
        vm.prank(admin);
        vm.expectRevert();
        engine.finalizeTrade(500e6, 0);

        // But emergency recall still works (tested in engine tests)

        // Unpause
        vm.prank(admin);
        engine.unpause();

        // Now operations work
        vm.prank(admin);
        engine.deployFunds(address(destination), 500e6);

        assertEq(vault.investedAssets(), 500e6);
    }

    // ============ Invariant: NO FEE ON LOSS ============

    function test_Invariant_NoFeeOnLoss() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        uint256 feeSharesBefore = vault.balanceOf(feeRecipient);

        // Multiple loss cycles
        for (uint256 i = 0; i < 3; i++) {
            uint256 available = vault.totalAssets() - vault.investedAssets();
            if (available < 100e6) break;

            vm.prank(admin);
            engine.deployFunds(address(destination), 100e6);

            vm.prank(admin);
            engine.reportLoss(50e6);

            destination.approveEngine(address(engine), 50e6);
            vm.prank(admin);
            engine.recallFunds(address(destination), 50e6);

            vm.prank(admin);
            engine.finalizeTrade(50e6, 0);
        }

        // INVARIANT: Fee shares must NOT increase from losses
        assertEq(
            vault.balanceOf(feeRecipient),
            feeSharesBefore,
            "NO FEE ON LOSS invariant violated"
        );
    }
}
