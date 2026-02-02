// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployConfig
 * @notice Network-specific configuration for AMEND Protocol deployment
 * @dev Contains addresses and parameters for each supported network
 */
abstract contract DeployConfig {
    // ============ Configuration Struct ============

    struct NetworkConfig {
        address usdc;           // USDC token address
        address admin;          // Engine admin (multisig recommended)
        address feeRecipient;   // Fee recipient (treasury)
        uint16 feeBps;          // Fee in basis points (max 2000 = 20%)
        string networkName;     // Human-readable network name
    }

    // ============ Network Configurations ============

    /**
     * @notice Base Mainnet Configuration
     * @dev USDC: Official Circle USDC on Base
     * @dev Admin/FeeRecipient: Set via environment variables for security
     */
    function getBaseMainnetConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, // Base USDC
            admin: address(0), // MUST be set via env
            feeRecipient: address(0), // MUST be set via env
            feeBps: 1000, // 10% default
            networkName: "Base Mainnet"
        });
    }

    /**
     * @notice Base Sepolia Testnet Configuration
     * @dev USDC: Testnet USDC on Base Sepolia
     * @dev Admin/FeeRecipient: Set via environment variables
     */
    function getBaseSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // Base Sepolia USDC
            admin: address(0), // MUST be set via env
            feeRecipient: address(0), // MUST be set via env
            feeBps: 1000, // 10% default
            networkName: "Base Sepolia"
        });
    }

    /**
     * @notice Local Anvil/Hardhat Configuration
     * @dev For local testing - all addresses are placeholders
     */
    function getLocalConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            usdc: address(0), // Deploy mock USDC locally
            admin: address(0), // Set via env or use deployer
            feeRecipient: address(0), // Set via env or use deployer
            feeBps: 1000, // 10%
            networkName: "Local"
        });
    }

    // ============ Config Selection ============

    /**
     * @notice Get configuration for current chain
     * @dev Reverts if chain is not supported
     * @return config The network configuration
     */
    function getConfigByChainId() internal view returns (NetworkConfig memory config) {
        if (block.chainid == 8453) {
            config = getBaseMainnetConfig();
        } else if (block.chainid == 84532) {
            config = getBaseSepoliaConfig();
        } else if (block.chainid == 31337) {
            config = getLocalConfig();
        } else {
            revert(string.concat("Unsupported chain ID: ", vm_toString(block.chainid)));
        }
    }

    /**
     * @dev Helper to convert uint to string (for error messages)
     */
    function vm_toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ============ Validation ============

    /**
     * @notice Validate that critical addresses are set
     * @param config The configuration to validate
     */
    function validateConfig(NetworkConfig memory config) internal pure {
        require(config.usdc != address(0), "DeployConfig: USDC address not set");
        require(config.admin != address(0), "DeployConfig: Admin address not set");
        require(config.feeRecipient != address(0), "DeployConfig: Fee recipient not set");
        require(config.feeBps <= 2000, "DeployConfig: Fee too high (max 20%)");
    }
}
