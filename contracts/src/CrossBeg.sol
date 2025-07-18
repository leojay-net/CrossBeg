// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IMailbox} from "hyperlane-monorepo/solidity/contracts/interfaces/IMailbox.sol";
import {IInterchainSecurityModule} from "hyperlane-monorepo/solidity/contracts/interfaces/IInterchainSecurityModule.sol";
import {TypeCasts} from "hyperlane-monorepo/solidity/contracts/libs/TypeCasts.sol";

/**
 * @title CrossBeg Payment Request Contract
 * @notice Handles cross-chain payment requests using Hyperlane messaging
 * @dev This contract manages payment requests and cross-chain messaging
 * Identity resolution is handled off-chain via ENS API
 */
contract CrossBegPaymentRequest {
    using TypeCasts for bytes32;
    using TypeCasts for address;

    // Events
    event PaymentRequestCreated(
        uint256 indexed requestId,
        address indexed requester,
        address indexed target,
        uint256 amount,
        string token,
        uint32 targetChain,
        string message,
        uint256 timestamp
    );
    
    event PaymentRequestReceived(
        uint256 indexed requestId,
        address indexed requester,
        address indexed target,
        uint256 amount,
        string token,
        uint32 originChain,
        string message,
        uint256 timestamp
    );
    
    event PaymentRequestFulfilled(
        uint256 indexed requestId,
        address indexed payer,
        uint256 amount,
        string token,
        string txHash
    );
    
    event PaymentRequestCancelled(
        uint256 indexed requestId,
        address indexed requester
    );
    
    event CrossChainMessageSent(
        uint256 indexed requestId,
        uint32 destinationChain,
        bytes32 messageId
    );

    // Structs
    struct PaymentRequest {
        uint256 id;
        address requester;
        address target;
        uint256 amount;
        string token; // Token symbol or address
        uint32 originChain;
        uint32 targetChain;
        string message;
        RequestStatus status;
        uint256 timestamp;
        uint256 expiryTime;
        string fulfillmentTxHash; // Transaction hash when fulfilled
    }

    enum RequestStatus {
        Pending,
        Fulfilled,
        Cancelled,
        Expired
    }

    // State variables
    IMailbox public immutable mailbox;
    uint32 public immutable localDomain;
    address public owner;
    
    mapping(uint256 => PaymentRequest) public paymentRequests;
    mapping(address => uint256[]) public userSentRequests; // User's sent request IDs
    mapping(address => uint256[]) public userReceivedRequests; // Requests received by user
    mapping(uint32 => address) public remoteCrossBegContracts; // Chain ID -> Contract address
    
    uint256 public nextRequestId;
    uint256 public constant DEFAULT_EXPIRY_TIME = 7 days;
    uint256 public constant MIN_EXPIRY_TIME = 1 hours;
    uint256 public constant MAX_EXPIRY_TIME = 30 days;

    // Access control
    modifier onlyMailbox() {
        require(msg.sender == address(mailbox), "CrossBeg: sender not mailbox");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "CrossBeg: not owner");
        _;
    }

    modifier onlyValidChain(uint32 chainId) {
        require(remoteCrossBegContracts[chainId] != address(0), "CrossBeg: chain not supported");
        _;
    }

    modifier requestExists(uint256 requestId) {
        require(paymentRequests[requestId].id != 0, "CrossBeg: request does not exist");
        _;
    }

    constructor(address _mailbox, uint32 _localDomain) {
        mailbox = IMailbox(_mailbox);
        localDomain = _localDomain;
        owner = msg.sender;
        nextRequestId = 1;
    }

    /**
     * @notice Transfer ownership of the contract
     * @param newOwner The new owner address
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CrossBeg: invalid new owner");
        owner = newOwner;
    }

    /**
     * @notice Set remote CrossBeg contract address for a specific chain
     * @param chainId The chain ID
     * @param contractAddress The contract address on that chain
     */
    function setRemoteContract(uint32 chainId, address contractAddress) external onlyOwner {
        remoteCrossBegContracts[chainId] = contractAddress;
    }

    /**
     * @notice Set multiple remote contracts at once
     * @param chainIds Array of chain IDs
     * @param contractAddresses Array of contract addresses
     */
    function setRemoteContracts(
        uint32[] calldata chainIds, 
        address[] calldata contractAddresses
    ) external onlyOwner {
        require(chainIds.length == contractAddresses.length, "CrossBeg: length mismatch");
        
        for (uint256 i = 0; i < chainIds.length; i++) {
            remoteCrossBegContracts[chainIds[i]] = contractAddresses[i];
        }
    }

    /**
     * @notice Create a payment request (local or cross-chain)
     * @param target The address to request payment from
     * @param amount The amount requested
     * @param token The token symbol or address
     * @param targetChain The chain where the target user is located
     * @param message Optional message with the request
     * @param expiryTime Custom expiry time (0 for default)
     */
    function createPaymentRequest(
        address target,
        uint256 amount,
        string memory token,
        uint32 targetChain,
        string memory message,
        uint256 expiryTime
    ) external payable returns (uint256) {
        require(target != address(0), "CrossBeg: invalid target address");
        require(amount > 0, "CrossBeg: amount must be greater than zero");
        require(target != msg.sender, "CrossBeg: cannot request from yourself");
        require(bytes(token).length > 0, "CrossBeg: token cannot be empty");

        // Set expiry time
        uint256 finalExpiryTime;
        if (expiryTime == 0) {
            finalExpiryTime = block.timestamp + DEFAULT_EXPIRY_TIME;
        } else {
            require(
                expiryTime >= MIN_EXPIRY_TIME && expiryTime <= MAX_EXPIRY_TIME,
                "CrossBeg: invalid expiry time"
            );
            finalExpiryTime = block.timestamp + expiryTime;
        }

        uint256 requestId = nextRequestId++;
        
        PaymentRequest storage request = paymentRequests[requestId];
        request.id = requestId;
        request.requester = msg.sender;
        request.target = target;
        request.amount = amount;
        request.token = token;
        request.originChain = localDomain;
        request.targetChain = targetChain;
        request.message = message;
        request.status = RequestStatus.Pending;
        request.timestamp = block.timestamp;
        request.expiryTime = finalExpiryTime;

        // Add to user's sent requests
        userSentRequests[msg.sender].push(requestId);

        emit PaymentRequestCreated(
            requestId,
            msg.sender,
            target,
            amount,
            token,
            targetChain,
            message,
            block.timestamp
        );

        // If cross-chain request, send message via Hyperlane
        if (targetChain != localDomain) {
            _sendCrossChainRequest(requestId, targetChain);
        } else {
            // Local request, add to target's received requests
            userReceivedRequests[target].push(requestId);
        }

        return requestId;
    }

    /**
     * @notice Send cross-chain payment request via Hyperlane
     * @param requestId The request ID to send
     * @param destinationChain The destination chain
     */
    function _sendCrossChainRequest(uint256 requestId, uint32 destinationChain) internal onlyValidChain(destinationChain) {
        PaymentRequest memory request = paymentRequests[requestId];
        
        // Encode the message
        bytes memory messageBody = abi.encode(
            request.id,
            request.requester,
            request.target,
            request.amount,
            request.token,
            request.originChain,
            request.message,
            request.timestamp,
            request.expiryTime
        );

        // Calculate required gas payment
        uint256 gasPayment = mailbox.quoteDispatch(
            destinationChain,
            remoteCrossBegContracts[destinationChain].addressToBytes32(),
            messageBody
        );

        require(msg.value >= gasPayment, "CrossBeg: insufficient gas payment");

        // Send the message
        bytes32 messageId = mailbox.dispatch{value: gasPayment}(
            destinationChain,
            remoteCrossBegContracts[destinationChain].addressToBytes32(),
            messageBody
        );

        emit CrossChainMessageSent(requestId, destinationChain, messageId);

        // Refund excess gas payment
        if (msg.value > gasPayment) {
            payable(msg.sender).transfer(msg.value - gasPayment);
        }
    }

    /**
     * @notice Handle incoming cross-chain messages from Hyperlane
     * @param _origin Domain of origin chain
     * @param _sender Address of sender on origin chain
     * @param _messageBody Raw message body
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _messageBody
    ) external onlyMailbox {
        // Verify the sender is a valid CrossBeg contract
        require(
            _sender.bytes32ToAddress() == remoteCrossBegContracts[_origin],
            "CrossBeg: invalid sender"
        );

        // Decode the message
        (
            uint256 requestId,
            address requester,
            address target,
            uint256 amount,
            string memory token,
            uint32 originChain,
            string memory message,
            uint256 timestamp,
            uint256 expiryTime
        ) = abi.decode(_messageBody, (uint256, address, address, uint256, string, uint32, string, uint256, uint256));

        require(block.timestamp < expiryTime, "CrossBeg: request expired");

        PaymentRequest storage request = paymentRequests[requestId];
        request.id = requestId;
        request.requester = requester;
        request.target = target;
        request.amount = amount;
        request.token = token;
        request.originChain = originChain;
        request.targetChain = localDomain;
        request.message = message;
        request.status = RequestStatus.Pending;
        request.timestamp = timestamp;
        request.expiryTime = expiryTime;

        userReceivedRequests[target].push(requestId);

        emit PaymentRequestReceived(
            requestId,
            requester,
            target,
            amount,
            token,
            originChain,
            message,
            timestamp
        );
    }

    /**
     * @notice Fulfill a payment request (mark as paid)
     * @param requestId The request ID to fulfill
     * @param txHash The transaction hash of the payment
     */
    function fulfillPaymentRequest(uint256 requestId, string memory txHash) external requestExists(requestId) {
        PaymentRequest storage request = paymentRequests[requestId];
        require(request.target == msg.sender, "CrossBeg: not the target of this request");
        require(request.status == RequestStatus.Pending, "CrossBeg: request not pending");
        require(block.timestamp < request.expiryTime, "CrossBeg: request expired");
        require(bytes(txHash).length > 0, "CrossBeg: transaction hash required");

        request.status = RequestStatus.Fulfilled;
        request.fulfillmentTxHash = txHash;

        emit PaymentRequestFulfilled(
            requestId,
            msg.sender,
            request.amount,
            request.token,
            txHash
        );
    }

    /**
     * @notice Cancel a payment request
     * @param requestId The request ID to cancel
     */
    function cancelPaymentRequest(uint256 requestId) external requestExists(requestId) {
        PaymentRequest storage request = paymentRequests[requestId];
        require(request.requester == msg.sender, "CrossBeg: not the requester");
        require(request.status == RequestStatus.Pending, "CrossBeg: request not pending");

        request.status = RequestStatus.Cancelled;

        emit PaymentRequestCancelled(requestId, msg.sender);
    }

    /**
     * @notice Mark expired requests as expired (anyone can call)
     * @param requestIds Array of request IDs to check
     */
    function markExpiredRequests(uint256[] calldata requestIds) external {
        for (uint256 i = 0; i < requestIds.length; i++) {
            PaymentRequest storage request = paymentRequests[requestIds[i]];
            if (request.id != 0 && 
                request.status == RequestStatus.Pending && 
                block.timestamp >= request.expiryTime) {
                request.status = RequestStatus.Expired;
            }
        }
    }

    /**
     * @notice Get user's sent requests
     * @param user The user address
     * @return Array of request IDs
     */
    function getUserSentRequests(address user) external view returns (uint256[] memory) {
        return userSentRequests[user];
    }

    /**
     * @notice Get user's received requests
     * @param user The user address
     * @return Array of request IDs
     */
    function getUserReceivedRequests(address user) external view returns (uint256[] memory) {
        return userReceivedRequests[user];
    }

    /**
     * @notice Get payment request details
     * @param requestId The request ID
     * @return The payment request struct
     */
    function getPaymentRequest(uint256 requestId) external view requestExists(requestId) returns (PaymentRequest memory) {
        return paymentRequests[requestId];
    }

    /**
     * @notice Get multiple payment requests
     * @param requestIds Array of request IDs
     * @return Array of payment request structs
     */
    function getPaymentRequests(uint256[] calldata requestIds) external view returns (PaymentRequest[] memory) {
        PaymentRequest[] memory requests = new PaymentRequest[](requestIds.length);
        for (uint256 i = 0; i < requestIds.length; i++) {
            requests[i] = paymentRequests[requestIds[i]];
        }
        return requests;
    }

    /**
     * @notice Quote gas cost for cross-chain request
     * @param destinationChain The destination chain
     * @param messageBody The message body
     * @return Gas cost in native token
     */
    function quoteGasPayment(uint32 destinationChain, bytes memory messageBody) external view returns (uint256) {
        require(remoteCrossBegContracts[destinationChain] != address(0), "CrossBeg: chain not supported");
        return mailbox.quoteDispatch(
            destinationChain,
            remoteCrossBegContracts[destinationChain].addressToBytes32(),
            messageBody
        );
    }

    /**
     * @notice Get supported chains
     * @param chainIds Array of chain IDs to check
     * @return Array of boolean values indicating support
     */
    function getSupportedChains(uint32[] calldata chainIds) external view returns (bool[] memory) {
        bool[] memory supported = new bool[](chainIds.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            supported[i] = remoteCrossBegContracts[chainIds[i]] != address(0);
        }
        return supported;
    }

    /**
     * @notice Emergency function to withdraw stuck funds
     */
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    /**
     * @notice Get contract stats
     * @return totalRequests Total requests created
     * @return currentRequestId Current request ID
     */
    function getContractStats() external view returns (uint256 totalRequests, uint256 currentRequestId) {
        return (nextRequestId - 1, nextRequestId);
    }

    // Fallback function to receive gas payments
    receive() external payable {}
}