#!/bin/bash

# CrossBeg Deployment Script
# Usage: ./deploy.sh <network> [verify]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if network is provided
if [ -z "$1" ]; then
    print_error "Network not specified!"
    echo "Usage: $0 <network> [verify]"
    echo "Supported networks: sepolia, mumbai, ethereum, polygon, arbitrum, optimism, base, bsc, avalanche"
    exit 1
fi

NETWORK=$1
VERIFY=$2

# Load environment variables
if [ -f .env ]; then
    print_info "Loading environment variables..."
    export $(cat .env | xargs)
else
    print_warning ".env file not found. Make sure to set environment variables manually."
fi

# Network configurations
case $NETWORK in
    "sepolia")
        RPC_URL=$SEPOLIA_RPC_URL
        ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
        VERIFIER_URL="https://api-sepolia.etherscan.io/api"
        ;;
    "mumbai")
        RPC_URL=$MUMBAI_RPC_URL
        ETHERSCAN_API_KEY=$POLYGONSCAN_API_KEY
        VERIFIER_URL="https://api-testnet.polygonscan.com/api"
        ;;
    "ethereum")
        RPC_URL=$ETHEREUM_RPC_URL
        ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY
        VERIFIER_URL="https://api.etherscan.io/api"
        ;;
    "polygon")
        RPC_URL=$POLYGON_RPC_URL
        ETHERSCAN_API_KEY=$POLYGONSCAN_API_KEY
        VERIFIER_URL="https://api.polygonscan.com/api"
        ;;
    "arbitrum")
        RPC_URL=$ARBITRUM_RPC_URL
        ETHERSCAN_API_KEY=$ARBISCAN_API_KEY
        VERIFIER_URL="https://api.arbiscan.io/api"
        ;;
    "optimism")
        RPC_URL=$OPTIMISM_RPC_URL
        ETHERSCAN_API_KEY=$OPTIMISTIC_ETHERSCAN_API_KEY
        VERIFIER_URL="https://api-optimistic.etherscan.io/api"
        ;;
    "base")
        RPC_URL=$BASE_RPC_URL
        ETHERSCAN_API_KEY=$BASESCAN_API_KEY
        VERIFIER_URL="https://api.basescan.org/api"
        ;;
    "bsc")
        RPC_URL=$BSC_RPC_URL
        ETHERSCAN_API_KEY=$BSCSCAN_API_KEY
        VERIFIER_URL="https://api.bscscan.com/api"
        ;;
    "avalanche")
        RPC_URL=$AVALANCHE_RPC_URL
        ETHERSCAN_API_KEY=$SNOWTRACE_API_KEY
        VERIFIER_URL="https://api.snowtrace.io/api"
        ;;
    *)
        print_error "Unsupported network: $NETWORK"
        exit 1
        ;;
esac

# Check if RPC URL is set
if [ -z "$RPC_URL" ]; then
    print_error "RPC URL for $NETWORK is not set!"
    exit 1
fi

print_info "Deploying CrossBeg to $NETWORK..."

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Deploy contract
print_info "Running deployment script..."
if [ "$VERIFY" = "verify" ] && [ -n "$ETHERSCAN_API_KEY" ]; then
    print_info "Verification enabled"
    forge script script/CrossBeg.s.sol:CrossBegDeployScript \
        --rpc-url $RPC_URL \
        --broadcast \
        --verify \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --verifier-url $VERIFIER_URL
else
    print_warning "Deploying without verification"
    forge script script/CrossBeg.s.sol:CrossBegDeployScript \
        --rpc-url $RPC_URL \
        --broadcast
fi

if [ $? -eq 0 ]; then
    print_success "Deployment completed successfully!"
    
    # Extract contract address from broadcast logs
    BROADCAST_DIR="broadcast/CrossBeg.s.sol"
    if [ -d "$BROADCAST_DIR" ]; then
        print_info "Checking deployment logs..."
        # This would need to be adjusted based on the actual broadcast log structure
        # For now, provide manual instructions
        print_info "Contract address can be found in the broadcast logs at: $BROADCAST_DIR"
    fi
    
    print_info "Next steps:"
    echo "1. Update your .env file with the deployed contract address:"
    echo "   CROSSBEG_ADDRESS=<deployed_contract_address>"
    echo "2. Verify the deployment:"
    echo "   ./deploy.sh $NETWORK verify-deployment"
    echo "3. Configure remote contracts after deploying to multiple chains:"
    echo "   ./deploy.sh $NETWORK configure-remote"
else
    print_error "Deployment failed!"
    exit 1
fi
