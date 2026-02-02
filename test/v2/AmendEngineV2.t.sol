// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

/// @notice Mock destination for deployment testing
contract MockDestination {
    IERC20 public immutable asset;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function approveEngine(address engine, uint256 amount) external {
        asset.approve(engine, amount);
    }
}

/**
 * @title AmendEngineV2Test
 * @author Abdulwahed Mansour
 * @notice Unit tests for AmendEngineV2
 */
contract AmendEngineV2Test is Test {
    AmendVaultV2 public vault;
    AmendEngineV2 public engine;
    MockUSDC public usdc;
    MockDestination public destination;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public reporter = address(0x3);
    address public emergency = address(0x4);
    address public feeRecipient = address(0x5);
    address public user1 = address(0x6);
    address public unauthorized = address(0x7);

    uint16 public constant FEE_BPS = 1000; // 10%

    // Events
    event WhitelistAdded(address indexed destination);
    event FundsDeployed(address indexed destination, uint256 amount);
    event TradeFinalized(uint256 principal, uint256 profit);
    event LossReported(uint256 loss);

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

        // Setup roles
        vm.startPrank(admin);
        engine.grantRole(engine.OPERATOR_ROLE(), operator);
        engine.grantRole(engine.REPORTER_ROLE(), reporter);
        engine.grantRole(engine.EMERGENCY_ROLE(), emergency);
        vm.stopPrank();

        // Deploy mock destination
        destination = new MockDestination(address(usdc));

        // Whitelist destination
        vm.prank(admin);
        engine.addToWhitelist(address(destination));

        // Fund accounts
        usdc.mint(user1, 10_000e6);
        usdc.mint(address(engine), 5_000e6); // Engine has funds for settlement

        // User deposits to vault
        vm.startPrank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(5_000e6, user1);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(engine.vault(), address(vault));
        assertEq(engine.asset(), address(usdc));
        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(engine.hasRole(engine.OPERATOR_ROLE(), admin));
        assertTrue(engine.hasRole(engine.REPORTER_ROLE(), admin));
        assertTrue(engine.hasRole(engine.EMERGENCY_ROLE(), admin));
    }

    // ============ Pause Tests ============

    function test_OnlyEmergencyCanPause() public {
        // Emergency role can pause
        vm.prank(emergency);
        engine.pause();
        assertTrue(engine.isPaused());

        // Unauthorized cannot pause
        vm.prank(unauthorized);
        vm.expectRevert();
        engine.pause();
    }

    function test_OnlyAdminCanUnpause() public {
        // Pause first
        vm.prank(emergency);
        engine.pause();

        // Emergency cannot unpause
        vm.prank(emergency);
        vm.expectRevert();
        engine.unpause();

        // Admin can unpause
        vm.prank(admin);
        engine.unpause();
        assertFalse(engine.isPaused());
    }

    // ============ Whitelist Tests ============

    function test_AddToWhitelist() public {
        address newDest = address(0x999);

        vm.expectEmit(true, false, false, false);
        emit WhitelistAdded(newDest);

        vm.prank(admin);
        engine.addToWhitelist(newDest);

        assertTrue(engine.isWhitelisted(newDest));
    }

    function test_AddToWhitelist_OnlyAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        engine.addToWhitelist(address(0x999));
    }

    // ============ Deploy Tests ============

    function test_DeployFunds_Success() public {
        vm.expectEmit(true, false, false, true);
        emit FundsDeployed(address(destination), 1000e6);

        vm.prank(operator);
        engine.deployFunds(address(destination), 1000e6);

        assertEq(engine.getDeployedTo(address(destination)), 1000e6);
        assertEq(engine.getTotalDeployed(), 1000e6);
        assertEq(vault.investedAssets(), 1000e6);
    }

    function test_DeployFunds_NotWhitelisted_Reverts() public {
        address notWhitelisted = address(0x888);

        vm.prank(operator);
        vm.expectRevert(AmendEngineV2.NotWhitelisted.selector);
        engine.deployFunds(notWhitelisted, 1000e6);
    }

    // ============ Finalize Trade Tests ============

    function test_FinalizeTrade_Success() public {
        // Deploy first
        vm.prank(operator);
        engine.deployFunds(address(destination), 1000e6);

        // Destination returns funds with profit
        destination.approveEngine(address(engine), 1100e6);
        usdc.mint(address(destination), 100e6); // Add profit

        vm.prank(operator);
        engine.recallFunds(address(destination), 1000e6);

        // Now engine has funds, finalize trade
        vm.expectEmit(false, false, false, true);
        emit TradeFinalized(1000e6, 100e6);

        vm.prank(reporter);
        engine.finalizeTrade(1000e6, 100e6);

        // Check vault received funds
        assertGt(usdc.balanceOf(address(vault)), 0);
    }

    function test_FinalizeTrade_EmptyTrade_Reverts() public {
        vm.prank(reporter);
        vm.expectRevert(AmendEngineV2.EmptyTrade.selector);
        engine.finalizeTrade(0, 0);
    }

    function test_FinalizeTrade_InsufficientBalance_Reverts() public {
        // Engine doesn't have enough
        vm.prank(reporter);
        vm.expectRevert(AmendEngineV2.InsufficientBalance.selector);
        engine.finalizeTrade(100_000e6, 0);
    }

    function test_FinalizeTrade_WhenPaused_Reverts() public {
        vm.prank(emergency);
        engine.pause();

        vm.prank(reporter);
        vm.expectRevert();
        engine.finalizeTrade(1000e6, 0);
    }

    // ============ Report Loss Tests ============

    function test_ReportLoss_Success() public {
        // Deploy first
        vm.prank(operator);
        engine.deployFunds(address(destination), 1000e6);

        vm.expectEmit(false, false, false, true);
        emit LossReported(200e6);

        vm.prank(reporter);
        engine.reportLoss(200e6);

        // Vault invested assets reduced
        assertEq(vault.investedAssets(), 800e6);
    }

    function test_ReportLoss_ZeroAmount_Reverts() public {
        vm.prank(reporter);
        vm.expectRevert(AmendEngineV2.ZeroAmount.selector);
        engine.reportLoss(0);
    }

    // ============ Emergency Tests ============

    function test_EmergencyRecall_WorksWhenPaused() public {
        // Deploy
        vm.prank(operator);
        engine.deployFunds(address(destination), 1000e6);

        // Destination approves engine
        destination.approveEngine(address(engine), 1000e6);

        // Pause
        vm.prank(emergency);
        engine.pause();

        // Emergency recall still works
        vm.prank(emergency);
        engine.emergencyRecall(address(destination));

        assertEq(engine.getDeployedTo(address(destination)), 0);
    }

    // ============ View Function Tests ============

    function test_GetDeployedTo() public {
        vm.prank(operator);
        engine.deployFunds(address(destination), 500e6);

        assertEq(engine.getDeployedTo(address(destination)), 500e6);
    }

    function test_GetTotalDeployed() public {
        vm.prank(operator);
        engine.deployFunds(address(destination), 500e6);

        assertEq(engine.getTotalDeployed(), 500e6);
    }
}
