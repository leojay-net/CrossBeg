// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {CrossBegPaymentRequest} from "../src/CrossBeg.sol";

/**
 * @title CrossBeg Deployment Script
 * @notice Deploys CrossBeg contracts to various networks
 * @dev This script handles deployment and configuration of CrossBeg contracts
 */
contract CrossBegDeployScript is Script {
    // Network configurations
    struct NetworkConfig {
        address mailbox;
        uint32 domain;
        string name;
    }

    // Hyperlane Mailbox addresses for different networks
    // These are the official Hyperlane Mailbox contract addresses
    mapping(uint256 => NetworkConfig) public networkConfigs;

    function setUp() public {
        // Ethereum Mainnet
        networkConfigs[1] = NetworkConfig({
            mailbox: 0xc005dc82818d67AF737725bD4bf75435d065D239,
            domain: 1,
            name: "Ethereum"
        });

        // Polygon
        networkConfigs[137] = NetworkConfig({
            mailbox: 0x5d934f4e2f797775e53561bB72aca21ba36B96BB,
            domain: 137,
            name: "Polygon"
        });

        // Arbitrum One
        networkConfigs[42161] = NetworkConfig({
            mailbox: 0x979Ca5202784112f4738403dBec5D0F3B9daabB9,
            domain: 42161,
            name: "Arbitrum"
        });

        // Optimism
        networkConfigs[10] = NetworkConfig({
            mailbox: 0xd4C1905BB1D26BC93DAC913e13CaCC278CdCC80D,
            domain: 10,
            name: "Optimism"
        });

        // Base
        networkConfigs[8453] = NetworkConfig({
            mailbox: 0xeA87ae93Fa0019a82A727bfd3eBd1cFCa8f64f1D,
            domain: 8453,
            name: "Base"
        });

        // BSC
        networkConfigs[56] = NetworkConfig({
            mailbox: 0x2971b9Aec44507F9C681B7E5aA5be474aB9F2E29,
            domain: 56,
            name: "BSC"
        });

        // Avalanche
        networkConfigs[43114] = NetworkConfig({
            mailbox: 0xFf06aFcaABaDDd1fb08371f9ccA15D73D51FeBD6,
            domain: 43114,
            name: "Avalanche"
        });

        // Sepolia Testnet
        networkConfigs[11155111] = NetworkConfig({
            mailbox: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766,
            domain: 11155111,
            name: "Sepolia"
        });

        // Mumbai Testnet
        networkConfigs[80001] = NetworkConfig({
            mailbox: 0x2d1889fe5B092CD988972261434F7E5f26041115,
            domain: 80001,
            name: "Mumbai"
        });

        // Arbitrum Goerli
        networkConfigs[421613] = NetworkConfig({
            mailbox: 0xCC737a94FecaeC165AbCf12dED095BB13F037685,
            domain: 421613,
            name: "Arbitrum Goerli"
        });
    }

    function run() public {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];

        require(config.mailbox != address(0), "Unsupported network");

        console.log("Deploying CrossBeg to", config.name);
        console.log("Chain ID:", chainId);
        console.log("Mailbox address:", config.mailbox);
        console.log("Domain:", config.domain);

        vm.startBroadcast();

        // Deploy CrossBeg contract
        CrossBegPaymentRequest crossBeg = new CrossBegPaymentRequest(
            config.mailbox,
            config.domain
        );

        vm.stopBroadcast();

        console.log("CrossBeg deployed at:", address(crossBeg));
        console.log("Owner:", crossBeg.owner());

        // Log deployment info
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", config.name);
        console.log("Chain ID:", chainId);
        console.log("CrossBeg Address:", address(crossBeg));
        console.log("Mailbox Address:", config.mailbox);
        console.log("Domain:", config.domain);
        console.log("Owner:", crossBeg.owner());
        console.log("========================\n");

        // Save deployment info to file
        _saveDeploymentInfo(chainId, address(crossBeg), config);
    }

    /**
     * @notice Deploy and configure contracts for multiple chains
     * @dev This function should be called after deploying to each chain individually
     */
    function configureRemoteContracts() public {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        require(config.mailbox != address(0), "Unsupported network");

        // You need to set the deployed contract address for the current chain
        // This should be updated after deployment
        address crossBegAddress = vm.envAddress("CROSSBEG_ADDRESS");
        
        require(crossBegAddress != address(0), "CrossBeg address not set");

        CrossBegPaymentRequest crossBeg = CrossBegPaymentRequest(payable(crossBegAddress));

        vm.startBroadcast();

        // Configure remote contracts
        // Add your remote contract addresses here after deploying to other chains
        
        // Example configuration (update with actual deployed addresses):
        /*
        if (chainId == 1) { // Ethereum
            crossBeg.setRemoteContract(137, POLYGON_CROSSBEG_ADDRESS);
            crossBeg.setRemoteContract(42161, ARBITRUM_CROSSBEG_ADDRESS);
            crossBeg.setRemoteContract(10, OPTIMISM_CROSSBEG_ADDRESS);
        } else if (chainId == 137) { // Polygon
            crossBeg.setRemoteContract(1, ETHEREUM_CROSSBEG_ADDRESS);
            crossBeg.setRemoteContract(42161, ARBITRUM_CROSSBEG_ADDRESS);
            crossBeg.setRemoteContract(10, OPTIMISM_CROSSBEG_ADDRESS);
        }
        // Add more configurations as needed
        */

        vm.stopBroadcast();

        console.log("Remote contracts configured for", config.name);
    }

    /**
     * @notice Verify deployment by checking contract state
     */
    function verifyDeployment() public view {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        address crossBegAddress = vm.envAddress("CROSSBEG_ADDRESS");
        require(crossBegAddress != address(0), "CrossBeg address not set");

        CrossBegPaymentRequest crossBeg = CrossBegPaymentRequest(payable(crossBegAddress));

        console.log("=== Deployment Verification ===");
        console.log("Network:", config.name);
        console.log("CrossBeg Address:", address(crossBeg));
        console.log("Mailbox:", address(crossBeg.mailbox()));
        console.log("Local Domain:", crossBeg.localDomain());
        console.log("Owner:", crossBeg.owner());
        console.log("Next Request ID:", crossBeg.nextRequestId());
        
        (uint256 totalRequests, uint256 currentRequestId) = crossBeg.getContractStats();
        console.log("Total Requests:", totalRequests);
        console.log("Current Request ID:", currentRequestId);
        console.log("==============================");
    }

    /**
     * @notice Get gas quote for deployment
     */
    function getDeploymentGasQuote() public view returns (uint256) {
        uint256 chainId = block.chainid;
        NetworkConfig memory config = networkConfigs[chainId];
        
        require(config.mailbox != address(0), "Unsupported network");

        // Estimate gas for deployment
        // This is an approximation based on the contract size
        uint256 estimatedGas = 4_200_000; // Approximate gas for CrossBeg deployment

        console.log("Estimated gas for deployment:", estimatedGas);
        console.log("Network:", config.name);
        
        return estimatedGas;
    }

    /**
     * @notice Save deployment information to a file
     */
    function _saveDeploymentInfo(
        uint256 chainId,
        address contractAddress,
        NetworkConfig memory config
    ) internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "network": "', config.name, '",\n',
            '  "chainId": ', vm.toString(chainId), ',\n',
            '  "crossBegAddress": "', vm.toString(contractAddress), '",\n',
            '  "mailboxAddress": "', vm.toString(config.mailbox), '",\n',
            '  "domain": ', vm.toString(config.domain), ',\n',
            '  "deployedAt": ', vm.toString(block.timestamp), '\n',
            "}"
        ));

        string memory filename = string(abi.encodePacked(
            "deployments/",
            config.name,
            "-",
            vm.toString(chainId),
            ".json"
        ));

        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }

    /**
     * @notice Emergency function to transfer ownership
     */
    function transferOwnership(address newOwner) public {
        address crossBegAddress = vm.envAddress("CROSSBEG_ADDRESS");
        require(crossBegAddress != address(0), "CrossBeg address not set");
        require(newOwner != address(0), "Invalid new owner");

        CrossBegPaymentRequest crossBeg = CrossBegPaymentRequest(payable(crossBegAddress));

        vm.startBroadcast();
        crossBeg.transferOwnership(newOwner);
        vm.stopBroadcast();

        console.log("Ownership transferred to:", newOwner);
    }

    /**
     * @notice Get supported networks
     */
    function getSupportedNetworks() public view {
        console.log("=== Supported Networks ===");
        console.log("1: Ethereum Mainnet");
        console.log("137: Polygon");
        console.log("42161: Arbitrum One");
        console.log("10: Optimism");
        console.log("8453: Base");
        console.log("56: BSC");
        console.log("43114: Avalanche");
        console.log("11155111: Sepolia Testnet");
        console.log("80001: Mumbai Testnet");
        console.log("421613: Arbitrum Goerli");
        console.log("=========================");
    }
}
