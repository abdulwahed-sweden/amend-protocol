// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IAmendVaultV2
 * @author Abdulwahed Mansour
 * @notice Interface for AMEND Vault with atomic settlement
 * @dev Key change: repay() replaces divest() + reportProfit()
 */
interface IAmendVaultV2 {
    // ============ Events ============
    event EngineUpdated(address indexed newEngine);
    event FeeParamsUpdated(address indexed feeRecipient, uint16 feeBps);
    event Invested(uint256 amount);
    event Repaid(uint256 principal, uint256 profit, uint256 feeAssets);
    event LossReported(uint256 loss);

    // ============ Errors ============
    error NotEngine();
    error ZeroAmount();
    error ZeroAddress();
    error FeeTooHigh();
    error PrincipalExceedsInvested();
    error LossExceedsInvested();
    error EmptyRepay();

    // ============ Admin Functions ============
    /// @notice Set the Engine address
    function setEngine(address newEngine) external;

    /// @notice Set fee parameters
    function setFeeParams(address newFeeRecipient, uint16 newFeeBps) external;

    // ============ Outbound Flow ============
    /// @notice Send funds to Engine for deployment
    function invest(uint256 amount) external;

    // ============ Inbound Flow (ATOMIC) ============
    /// @notice Unified settlement - Vault PULLS principal + profit
    /// @param principal Original capital being returned
    /// @param profit Earned profit (0 if none)
    function repay(uint256 principal, uint256 profit) external;

    /// @notice Report loss - NO FEES EVER
    function reportLoss(uint256 loss) external;

    // ============ View Functions ============
    function asset() external view returns (address);
    function engine() external view returns (address);
    function feeRecipient() external view returns (address);
    function managementFeeBps() external view returns (uint16);
    function investedAssets() external view returns (uint256);
}
