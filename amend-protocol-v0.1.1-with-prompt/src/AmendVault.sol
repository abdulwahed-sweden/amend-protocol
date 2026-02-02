// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20}  from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20}   from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AMEND Vault (MVP)
 * @notice Islamic-compliant DeFi vault with profit-sharing model
 * @dev Asset: USDC (or any ERC20), Shares: AMEND Vault Shares (ERC4626)
 *
 * Core Invariant:
 * - Protocol fee is charged ONLY when there is realized profit.
 * - If there is loss, protocol takes ZERO fee.
 *
 * RWA/Offchain exposure is abstracted behind `engine`.
 * For v0.1, profit/loss is "realized" only when engine returns assets.
 */
contract AmendVault is ERC4626, Ownable, ReentrancyGuard {
    
    /// @notice Engine is the only entity allowed to move funds for external deployment
    address public engine;

    /// @notice Fee recipient (treasury)
    address public feeRecipient;

    /// @notice Management fee in basis points (e.g., 200 = 2.00%)
    uint16 public managementFeeBps;

    /// @notice Tracks assets deployed outside the vault (accounting only)
    uint256 public investedAssets;

    /// @notice Simple epoch accounting
    uint64 public lastReportTimestamp;

    // ============ Events ============
    
    event EngineUpdated(address indexed newEngine);
    event FeeParamsUpdated(address indexed feeRecipient, uint16 feeBps);
    event Invested(uint256 assets);
    event Divested(uint256 assetsReturned);
    event ProfitReported(uint256 grossProfit, uint256 feeAssets);
    event LossReported(uint256 lossAssets);

    // ============ Modifiers ============
    
    modifier onlyEngine() {
        require(msg.sender == engine, "AMEND: not engine");
        _;
    }

    // ============ Constructor ============
    
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        address feeRecipient_,
        uint16 managementFeeBps_
    )
        ERC20(name_, symbol_)
        ERC4626(asset_)
        Ownable(owner_)
    {
        require(feeRecipient_ != address(0), "AMEND: feeRecipient=0");
        require(managementFeeBps_ <= 2000, "AMEND: fee too high"); // cap 20% for safety
        feeRecipient = feeRecipient_;
        managementFeeBps = managementFeeBps_;
        lastReportTimestamp = uint64(block.timestamp);
    }

    // ============ Admin / Governance ============

    /// @notice Set the engine address (only owner)
    function setEngine(address newEngine) external onlyOwner {
        require(newEngine != address(0), "AMEND: engine=0");
        engine = newEngine;
        emit EngineUpdated(newEngine);
    }

    /// @notice Update fee parameters (only owner)
    function setFeeParams(address newFeeRecipient, uint16 newFeeBps) external onlyOwner {
        require(newFeeRecipient != address(0), "AMEND: feeRecipient=0");
        require(newFeeBps <= 2000, "AMEND: fee too high");
        feeRecipient = newFeeRecipient;
        managementFeeBps = newFeeBps;
        emit FeeParamsUpdated(newFeeRecipient, newFeeBps);
    }

    // ============ NAV Accounting ============
    
    /**
     * @notice ERC4626 uses totalAssets() to compute share price
     * @dev NAV = on-chain USDC balance + investedAssets (tracked)
     * @return Total assets under management
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + investedAssets;
    }

    // ============ Engine: invest/divest ============
    
    /**
     * @notice Move assets from vault to engine for external deployment
     * @dev This does NOT change share balances; it only changes where assets live
     * @param assets Amount of assets to invest
     */
    function invest(uint256 assets) external onlyEngine nonReentrant {
        require(assets > 0, "AMEND: assets=0");

        // Transfer to engine
        IERC20(asset()).transfer(engine, assets);

        // Increase invested accounting
        investedAssets += assets;

        emit Invested(assets);
    }

    /**
     * @notice Engine returns assets back to the vault
     * @dev Decreases investedAssets and increases on-chain balance
     * @param assetsReturned Amount of assets being returned
     */
    function divest(uint256 assetsReturned) external onlyEngine nonReentrant {
        require(assetsReturned > 0, "AMEND: assets=0");

        // Pull funds back from engine (engine must approve the vault)
        bool ok = IERC20(asset()).transferFrom(engine, address(this), assetsReturned);
        require(ok, "AMEND: transferFrom failed");

        // Decrease invested accounting (bounded to prevent underflow)
        if (assetsReturned >= investedAssets) {
            investedAssets = 0;
        } else {
            investedAssets -= assetsReturned;
        }

        emit Divested(assetsReturned);
    }

    // ============ Profit / Loss Reporting ============
    
    /**
     * @notice Report realized PROFIT in asset units (USDC)
     * @dev Fee is taken ONLY here (grossProfit > 0)
     *      Fee is minted as shares to feeRecipient to avoid draining vault liquidity
     * @dev TRUST BOUNDARY: Profit must be backed by actual assets in vault
     * @param grossProfitAssets The gross profit amount in asset units
     */
    function reportProfit(uint256 grossProfitAssets) external onlyEngine nonReentrant {
        require(grossProfitAssets > 0, "AMEND: profit=0");
        
        // ✅ FIX #2: Verify profit is backed by actual on-chain balance
        uint256 onChainBalance = IERC20(asset()).balanceOf(address(this));
        require(
            onChainBalance >= grossProfitAssets, 
            "AMEND: profit not backed by assets"
        );

        // Calculate fee in assets
        uint256 feeAssets = (grossProfitAssets * managementFeeBps) / 10_000;

        // Mint fee shares to recipient (dilution-based fee)
        if (feeAssets > 0) {
            _mintFeeShares(feeAssets);
        }

        lastReportTimestamp = uint64(block.timestamp);
        emit ProfitReported(grossProfitAssets, feeAssets);
    }

    /**
     * @notice Report realized LOSS in asset units
     * @dev INVARIANT: NO fee on loss - this is the core promise of AMEND
     * @dev TRUST BOUNDARY: Engine must report accurate loss. Loss cannot exceed invested amount.
     * @param lossAssets The loss amount in asset units
     */
    function reportLoss(uint256 lossAssets) external onlyEngine nonReentrant {
        require(lossAssets > 0, "AMEND: loss=0");
        require(lossAssets <= investedAssets, "AMEND: loss > invested"); // ✅ FIX #1: Validate loss bounds

        // ⚠️ NO FEES HERE - CORE INVARIANT ⚠️
        
        // Reduce investedAssets to reflect the loss (NAV decreases)
        investedAssets -= lossAssets;

        lastReportTimestamp = uint64(block.timestamp);
        emit LossReported(lossAssets);
    }

    /**
     * @notice Mint shares equivalent to feeAssets to feeRecipient
     * @dev Uses ERC4626 conversion at current share price (before mint)
     * @param feeAssets The fee amount in asset units
     */
    function _mintFeeShares(uint256 feeAssets) internal {
        // Convert assets to shares using ERC4626 logic
        uint256 feeShares = convertToShares(feeAssets);
        if (feeShares == 0) return;

        _mint(feeRecipient, feeShares);
    }

    // ============ Safety Functions ============
    
    /**
     * @notice Rescue accidentally sent tokens (not the vault asset)
     * @param token The token to rescue
     * @param amount Amount to rescue
     * @param to Recipient address
     */
    function rescueTokens(address token, uint256 amount, address to) external onlyOwner {
        require(token != address(asset()), "AMEND: cannot rescue asset");
        IERC20(token).transfer(to, amount);
    }
}
