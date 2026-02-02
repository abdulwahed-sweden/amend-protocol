// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IAmendVaultV2} from "./interfaces/IAmendVaultV2.sol";

/**
 * @title AmendVaultV2
 * @author Abdulwahed Mansour
 * @notice Islamic-compliant DeFi vault with atomic settlement
 * @dev Implements "Vault Pulls Always" architecture
 *
 * CORE INVARIANT: NO FEE ON LOSS
 * Fees are minted ONLY from realized profit, never from losses.
 *
 * Key Change from v0.1.1:
 * - repay(principal, profit) replaces divest() + reportProfit()
 * - Single atomic settlement path
 * - Vault pulls funds from Engine (not pushed)
 */
contract AmendVaultV2 is IAmendVaultV2, ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint16 public constant MAX_FEE_BPS = 2000; // 20% maximum fee

    // ============ State Variables ============
    address public override engine;
    address public override feeRecipient;
    uint16 public override managementFeeBps;
    uint256 public override investedAssets;

    // ============ Modifiers ============
    modifier onlyEngine() {
        if (msg.sender != engine) revert NotEngine();
        _;
    }

    // ============ Constructor ============
    /**
     * @notice Initialize the vault
     * @param _asset Underlying asset (e.g., USDC)
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     * @param _owner Initial owner address
     * @param _feeRecipient Address to receive fees
     * @param _feeBps Fee in basis points (100 = 1%)
     */
    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _owner,
        address _feeRecipient,
        uint16 _feeBps
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(_owner) {
        if (address(_asset) == address(0)) revert ZeroAddress();
        if (_feeRecipient == address(0)) revert ZeroAddress();
        if (_feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        feeRecipient = _feeRecipient;
        managementFeeBps = _feeBps;
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the Engine address
     * @param newEngine New engine address
     */
    function setEngine(address newEngine) external override onlyOwner {
        if (newEngine == address(0)) revert ZeroAddress();
        engine = newEngine;
        emit EngineUpdated(newEngine);
    }

    /**
     * @notice Update fee parameters
     * @param newFeeRecipient New fee recipient address
     * @param newFeeBps New fee in basis points
     */
    function setFeeParams(address newFeeRecipient, uint16 newFeeBps) external override onlyOwner {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        feeRecipient = newFeeRecipient;
        managementFeeBps = newFeeBps;
        emit FeeParamsUpdated(newFeeRecipient, newFeeBps);
    }

    // ============ Outbound Flow ============

    /**
     * @notice Send funds to Engine for deployment
     * @dev Only callable by Engine
     * @param amount Amount to invest
     */
    function invest(uint256 amount) external override onlyEngine nonReentrant {
        if (amount == 0) revert ZeroAmount();

        investedAssets += amount;
        IERC20(asset()).safeTransfer(engine, amount);

        emit Invested(amount);
    }

    // ============ Inbound Flow (ATOMIC) ============

    /**
     * @notice Atomic settlement - Vault PULLS funds from Engine
     * @dev Replaces divest() + reportProfit() from v0.1.1
     * @param principal Original capital being returned
     * @param profit Earned profit (0 if break-even)
     */
    function repay(uint256 principal, uint256 profit) external override onlyEngine nonReentrant {
        // ===== CHECKS =====
        if (principal > investedAssets) revert PrincipalExceedsInvested();
        if (principal + profit == 0) revert EmptyRepay();

        // ===== EFFECTS (before external calls!) =====
        investedAssets -= principal;

        // ===== INTERACTIONS =====
        uint256 total = principal + profit;
        IERC20(asset()).safeTransferFrom(engine, address(this), total);

        // ===== FEE LOGIC (only on profit) =====
        uint256 feeAssets = 0;
        if (profit > 0 && managementFeeBps > 0) {
            feeAssets = (profit * managementFeeBps) / 10_000;
            if (feeAssets > 0) {
                _mintFeeShares(feeAssets);
            }
        }

        emit Repaid(principal, profit, feeAssets);
    }

    /**
     * @notice Report loss - INVARIANT: NO FEE EVER
     * @param loss Amount of capital lost
     */
    function reportLoss(uint256 loss) external override onlyEngine nonReentrant {
        if (loss == 0) revert ZeroAmount();
        if (loss > investedAssets) revert LossExceedsInvested();

        investedAssets -= loss;

        // NO FEE MINTING - CORE INVARIANT
        // This is the ethical foundation of AMEND Protocol

        emit LossReported(loss);
    }

    // ============ ERC4626 Overrides ============

    /**
     * @notice Get the underlying asset address
     * @return Asset address
     */
    function asset() public view override(ERC4626, IAmendVaultV2) returns (address) {
        return super.asset();
    }

    /**
     * @notice Total assets = on-chain balance + invested assets
     * @return Total assets under management
     */
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + investedAssets;
    }

    // ============ Internal Functions ============

    /**
     * @notice Mint fee shares to fee recipient
     * @dev Uses share dilution for fair fee extraction
     * @param feeAssets Amount of assets to convert to fee shares
     */
    function _mintFeeShares(uint256 feeAssets) internal {
        uint256 feeShares = convertToShares(feeAssets);
        if (feeShares > 0) {
            _mint(feeRecipient, feeShares);
        }
    }

    /**
     * @notice Rescue tokens accidentally sent to vault
     * @param token Token to rescue
     * @param to Recipient address
     * @param amount Amount to rescue
     */
    function rescueTokens(address token, address to, uint256 amount) external onlyOwner {
        if (token == asset()) {
            // Cannot rescue the underlying asset
            uint256 excess = IERC20(token).balanceOf(address(this)) -
                (totalAssets() - investedAssets);
            require(amount <= excess, "AMEND: cannot rescue vault assets");
        }
        IERC20(token).safeTransfer(to, amount);
    }
}
