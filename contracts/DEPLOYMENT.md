# CrossBeg Deployment Guide

This guide explains how to deploy the CrossBeg smart contracts to various networks.

## Prerequisites

1. Install Foundry (forge, cast, anvil)
2. Set up your environment variables
3. Have the necessary tokens for gas fees

## Environment Setup

Create a `.env` file in the contracts directory:

```bash
# Private key for deployment (use a dedicated deployment wallet)
PRIVATE_KEY=your_private_key_here

# RPC URLs for different networks
ETHEREUM_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/your_key
POLYGON_RPC_URL=https://polygon-mainnet.alchemyapi.io/v2/your_key
ARBITRUM_RPC_URL=https://arb-mainnet.alchemyapi.io/v2/your_key
OPTIMISM_RPC_URL=https://opt-mainnet.alchemyapi.io/v2/your_key
BASE_RPC_URL=https://base-mainnet.alchemyapi.io/v2/your_key

# Testnet RPC URLs
SEPOLIA_RPC_URL=https://eth-sepolia.alchemyapi.io/v2/your_key
MUMBAI_RPC_URL=https://polygon-mumbai.alchemyapi.io/v2/your_key

# Etherscan API keys for verification
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key
OPTIMISTIC_ETHERSCAN_API_KEY=your_optimistic_etherscan_api_key
BASESCAN_API_KEY=your_basescan_api_key

# After deployment, set the contract address
CROSSBEG_ADDRESS=deployed_contract_address
```

## Deployment Commands

### Deploy to Testnet (Sepolia)

```bash
# Deploy to Sepolia testnet
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Verify deployment
CROSSBEG_ADDRESS=<deployed_address> forge script script/CrossBeg.s.sol:CrossBegDeployScript --sig "verifyDeployment()" --rpc-url $SEPOLIA_RPC_URL
```

### Deploy to Mainnet

```bash
# Deploy to Ethereum
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $ETHEREUM_RPC_URL --broadcast --verify

# Deploy to Polygon
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $POLYGON_RPC_URL --broadcast --verify

# Deploy to Arbitrum
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $ARBITRUM_RPC_URL --broadcast --verify

# Deploy to Optimism
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $OPTIMISM_RPC_URL --broadcast --verify

# Deploy to Base
forge script script/CrossBeg.s.sol:CrossBegDeployScript --rpc-url $BASE_RPC_URL --broadcast --verify
```

### Configure Remote Contracts

After deploying to multiple chains, configure the remote contract addresses:

```bash
# Update .env with the deployed contract address
export CROSSBEG_ADDRESS=<deployed_address>

# Configure remote contracts
forge script script/CrossBeg.s.sol:CrossBegDeployScript --sig "configureRemoteContracts()" --rpc-url $ETHEREUM_RPC_URL --broadcast
```

## Gas Estimation

Get gas estimates before deployment:

```bash
forge script script/CrossBeg.s.sol:CrossBegDeployScript --sig "getDeploymentGasQuote()" --rpc-url $SEPOLIA_RPC_URL
```

## Verification

Verify contracts on block explorers:

```bash
# Ethereum
forge verify-contract <contract_address> src/CrossBeg.sol:CrossBegPaymentRequest --etherscan-api-key $ETHERSCAN_API_KEY

# Polygon
forge verify-contract <contract_address> src/CrossBeg.sol:CrossBegPaymentRequest --etherscan-api-key $POLYGONSCAN_API_KEY --verifier-url https://api.polygonscan.com/api

# Arbitrum
forge verify-contract <contract_address> src/CrossBeg.sol:CrossBegPaymentRequest --etherscan-api-key $ARBISCAN_API_KEY --verifier-url https://api.arbiscan.io/api
```

## Deployment Flow

1. **Test Locally**: Run tests to ensure contracts work correctly
2. **Deploy to Testnet**: Deploy to Sepolia or other testnets first
3. **Test Cross-Chain**: Test cross-chain functionality on testnets
4. **Deploy to Mainnet**: Deploy to production networks
5. **Configure Remote Contracts**: Set up cross-chain contract addresses
6. **Verify Contracts**: Verify on block explorers

## Network Information

| Network | Chain ID | Hyperlane Domain | Mailbox Address |
|---------|----------|------------------|-----------------|
| Ethereum | 1 | 1 | 0xc005dc82818d67AF737725bD4bf75435d065D239 |
| Polygon | 137 | 137 | 0x5d934f4e2f797775e53561bB72aca21ba36B96BB |
| Arbitrum | 42161 | 42161 | 0x979Ca5202784112f4738403dBec5D0F3B9daabB9 |
| Optimism | 10 | 10 | 0xd4C1905BB1D26BC93DAC913e13CaCC278CdCC80D |
| Base | 8453 | 8453 | 0xeA87ae93Fa0019a82A727bfd3eBd1cFCa8f64f1D |
| Sepolia | 11155111 | 11155111 | 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766 |

## Security Considerations

1. **Use a dedicated deployment wallet** with only necessary funds
2. **Verify contract source code** on block explorers
3. **Test thoroughly** on testnets before mainnet deployment
4. **Set up proper access controls** and ownership management
5. **Monitor deployed contracts** for any issues

## Troubleshooting

### Common Issues

1. **Insufficient gas**: Increase gas limit or gas price
2. **RPC rate limits**: Use multiple RPC providers or paid tiers
3. **Contract verification fails**: Check compiler version and optimization settings
4. **Cross-chain messages fail**: Verify Hyperlane mailbox addresses and domains

### Getting Help

- Check Foundry documentation: https://book.getfoundry.sh/
- Hyperlane documentation: https://docs.hyperlane.xyz/
- OpenZeppelin documentation for security best practices

## Post-Deployment Checklist

- [ ] Contract deployed successfully
- [ ] Contract verified on block explorer
- [ ] Ownership configured correctly
- [ ] Remote contracts configured (for cross-chain)
- [ ] Gas limits and fees tested
- [ ] Cross-chain messaging tested
- [ ] Documentation updated with contract addresses
- [ ] Frontend/backend updated with new contract addresses
