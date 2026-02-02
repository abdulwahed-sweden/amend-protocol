#!/bin/bash

# AMEND Protocol - Setup Script
# Run this after cloning the project

echo "🚀 Setting up AMEND Protocol..."

# Check if forge is installed
if ! command -v forge &> /dev/null; then
    echo "❌ Foundry not found. Installing..."
    curl -L https://foundry.paradigm.xyz | bash
    source ~/.bashrc
    foundryup
fi

echo "📦 Installing dependencies..."

# Install OpenZeppelin contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Install forge-std for testing
forge install foundry-rs/forge-std --no-commit

echo "🔨 Building contracts..."
forge build

echo "🧪 Running tests..."
forge test -vv

echo ""
echo "✅ Setup complete!"
echo ""
echo "Commands you can use:"
echo "  forge test -vv                    # Run all tests"
echo "  forge test --match-test NoFee -vvv  # Run specific test"
echo "  forge coverage                    # Check coverage"
echo ""
