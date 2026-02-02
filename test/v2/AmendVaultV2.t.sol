// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AmendVaultV2} from "../../src/v2/AmendVaultV2.sol";
import {IAmendVaultV2} from "../../src/v2/interfaces/IAmendVaultV2.sol";

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

/**
 * @title AmendVaultV2Test
 * @author Abdulwahed Mansour
 * @notice Unit tests for AmendVaultV2
 */
contract AmendVaultV2Test is Test {
    AmendVaultV2 public vault;
    MockUSDC public usdc;

    address public owner = address(0x1);
    address public engine = address(0x2);
    address public feeRecipient = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);

    uint16 public constant FEE_BPS = 1000; // 10%

    // Events
    event EngineUpdated(address indexed newEngine);
    event Invested(uint256 amount);
    event Repaid(uint256 principal, uint256 profit, uint256 feeAssets);
    event LossReported(uint256 loss);

    function setUp() public {
        usdc = new MockUSDC();

        vm.prank(owner);
        vault = new AmendVaultV2(
            IERC20(address(usdc)),
            "AMEND Vault V2",
            "avUSDC",
            owner,
            feeRecipient,
            FEE_BPS
        );

        // Set engine
        vm.prank(owner);
        vault.setEngine(engine);

        // Fund users
        usdc.mint(user1, 10_000e6);
        usdc.mint(user2, 10_000e6);
        usdc.mint(engine, 10_000e6);

        // Approve vault
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(engine);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ Setup Tests ============

    function test_Constructor() public view {
        assertEq(vault.asset(), address(usdc));
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.managementFeeBps(), FEE_BPS);
        assertEq(vault.owner(), owner);
        assertEq(vault.engine(), engine);
    }

    function test_SetEngine() public {
        address newEngine = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit EngineUpdated(newEngine);

        vm.prank(owner);
        vault.setEngine(newEngine);

        assertEq(vault.engine(), newEngine);
    }

    function test_SetEngine_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.setEngine(address(0x999));
    }

    // ============ Invest Tests ============

    function test_Invest_Success() public {
        // User deposits first
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        // Engine invests
        vm.expectEmit(false, false, false, true);
        emit Invested(500e6);

        vm.prank(engine);
        vault.invest(500e6);

        assertEq(vault.investedAssets(), 500e6);
        assertEq(usdc.balanceOf(engine), 10_000e6 + 500e6);
    }

    function test_Invest_OnlyEngine() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(user1);
        vm.expectRevert(IAmendVaultV2.NotEngine.selector);
        vault.invest(500e6);
    }

    function test_Invest_ZeroAmount_Reverts() public {
        vm.prank(engine);
        vm.expectRevert(IAmendVaultV2.ZeroAmount.selector);
        vault.invest(0);
    }

    // ============ Repay Tests ============

    function test_Repay_Success() public {
        // Setup: deposit and invest
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        // Repay with profit
        vm.expectEmit(false, false, false, true);
        emit Repaid(1000e6, 100e6, 10e6); // 10% fee on 100 profit

        vm.prank(engine);
        vault.repay(1000e6, 100e6);

        assertEq(vault.investedAssets(), 0);
        assertEq(usdc.balanceOf(address(vault)), 1100e6);
    }

    function test_Repay_PrincipalOnly() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vm.prank(engine);
        vault.repay(1000e6, 0);

        // No fee on zero profit
        assertEq(vault.balanceOf(feeRecipient), feeRecipientSharesBefore);
        assertEq(vault.investedAssets(), 0);
    }

    function test_Repay_ProfitOnly() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(500e6);

        // Repay 0 principal, just profit
        vm.prank(engine);
        vault.repay(0, 100e6);

        // 500 still invested
        assertEq(vault.investedAssets(), 500e6);
        // Fee recipient got shares
        assertGt(vault.balanceOf(feeRecipient), 0);
    }

    function test_Repay_PrincipalAndProfit() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vm.prank(engine);
        vault.repay(800e6, 200e6);

        // 200 still invested
        assertEq(vault.investedAssets(), 200e6);
        // Fee recipient got shares for 200 * 10% = 20 profit fee
        assertGt(vault.balanceOf(feeRecipient), feeRecipientSharesBefore);
    }

    function test_Repay_PrincipalExceedsInvested_Reverts() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(500e6);

        vm.prank(engine);
        vm.expectRevert(IAmendVaultV2.PrincipalExceedsInvested.selector);
        vault.repay(600e6, 0); // Only 500 invested
    }

    function test_Repay_EmptyRepay_Reverts() public {
        vm.prank(engine);
        vm.expectRevert(IAmendVaultV2.EmptyRepay.selector);
        vault.repay(0, 0);
    }

    function test_Repay_FeesOnlyFromProfit() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        // Repay with NO profit
        vm.prank(engine);
        vault.repay(1000e6, 0);

        // NO fee shares minted
        assertEq(vault.balanceOf(feeRecipient), feeRecipientSharesBefore);
    }

    function test_Repay_OnlyEngine() public {
        vm.prank(user1);
        vm.expectRevert(IAmendVaultV2.NotEngine.selector);
        vault.repay(100e6, 0);
    }

    // ============ Loss Tests ============

    function test_ReportLoss_Success() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        vm.expectEmit(false, false, false, true);
        emit LossReported(200e6);

        vm.prank(engine);
        vault.reportLoss(200e6);

        assertEq(vault.investedAssets(), 800e6);
    }

    function test_ReportLoss_ExceedsInvested_Reverts() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(500e6);

        vm.prank(engine);
        vm.expectRevert(IAmendVaultV2.LossExceedsInvested.selector);
        vault.reportLoss(600e6);
    }

    function test_ReportLoss_NoFees() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vm.prank(engine);
        vault.reportLoss(500e6);

        // CORE INVARIANT: NO FEE ON LOSS
        assertEq(vault.balanceOf(feeRecipient), feeRecipientSharesBefore);
    }

    function testFuzz_ReportLoss_NeverMintsFees(uint256 loss) public {
        // Bound loss to reasonable range
        loss = bound(loss, 1, 1000e6);

        vm.prank(user1);
        vault.deposit(1000e6, user1);

        vm.prank(engine);
        vault.invest(1000e6);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);

        vm.prank(engine);
        vault.reportLoss(loss);

        // INVARIANT: Fee recipient shares MUST NOT increase on loss
        assertEq(
            vault.balanceOf(feeRecipient),
            feeRecipientSharesBefore,
            "NO FEE ON LOSS invariant violated"
        );
    }

    // ============ ERC4626 Tests ============

    function test_TotalAssets_IncludesInvested() public {
        vm.prank(user1);
        vault.deposit(1000e6, user1);

        assertEq(vault.totalAssets(), 1000e6);

        vm.prank(engine);
        vault.invest(500e6);

        // Total assets unchanged (500 on-chain + 500 invested)
        assertEq(vault.totalAssets(), 1000e6);
    }

    function test_Deposit_Withdraw_Cycle() public {
        // Deposit
        vm.prank(user1);
        uint256 shares = vault.deposit(1000e6, user1);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(user1), shares);

        // Withdraw
        vm.prank(user1);
        vault.withdraw(1000e6, user1, user1);

        assertEq(vault.balanceOf(user1), 0);
        assertEq(usdc.balanceOf(user1), 10_000e6);
    }
}
