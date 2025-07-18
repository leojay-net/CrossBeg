// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {CrossBegPaymentRequest} from "../src/CrossBeg.sol";

// Mock Hyperlane Mailbox for testing
contract MockMailbox {
    mapping(uint32 => mapping(bytes32 => bytes)) public dispatched;
    uint256 public constant QUOTE_GAS_PAYMENT = 0.001 ether;
    
    event Dispatch(
        address indexed sender,
        uint32 indexed destination,
        bytes32 indexed recipient,
        bytes message
    );
    
    function dispatch(
        uint32 destination,
        bytes32 recipient,
        bytes calldata messageBody
    ) external payable returns (bytes32) {
        require(msg.value >= QUOTE_GAS_PAYMENT, "MockMailbox: insufficient gas");
        
        bytes32 messageId = keccak256(abi.encode(destination, recipient, messageBody, block.timestamp));
        dispatched[destination][recipient] = messageBody;
        
        emit Dispatch(msg.sender, destination, recipient, messageBody);
        return messageId;
    }
    
    function quoteDispatch(
        uint32,
        bytes32,
        bytes calldata
    ) external pure returns (uint256) {
        return QUOTE_GAS_PAYMENT;
    }
    
    // Helper function to simulate cross-chain message delivery
    function deliverMessage(
        address crossBegContract,
        uint32 origin,
        bytes32 sender,
        bytes calldata messageBody
    ) external {
        CrossBegPaymentRequest(payable(crossBegContract)).handle(origin, sender, messageBody);
    }
}

contract CrossBegPaymentRequestTest is Test {
    CrossBegPaymentRequest public crossBeg;
    MockMailbox public mockMailbox;
    
    address public owner = address(this);
    address public user1 = address(0x100);
    address public user2 = address(0x200);
    address public user3 = address(0x300);
    
    uint32 public constant LOCAL_DOMAIN = 1;
    uint32 public constant REMOTE_DOMAIN = 2;
    
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

    function setUp() public {
        mockMailbox = new MockMailbox();
        crossBeg = new CrossBegPaymentRequest(address(mockMailbox), LOCAL_DOMAIN);
        
        // Setup remote contract
        crossBeg.setRemoteContract(REMOTE_DOMAIN, address(crossBeg));
        
        // Fund users with ETH
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }

    function test_Constructor() public view {
        assertEq(address(crossBeg.mailbox()), address(mockMailbox));
        assertEq(crossBeg.localDomain(), LOCAL_DOMAIN);
        assertEq(crossBeg.owner(), owner);
        assertEq(crossBeg.nextRequestId(), 1);
    }

    function test_TransferOwnership() public {
        crossBeg.transferOwnership(user1);
        assertEq(crossBeg.owner(), user1);
    }

    function test_TransferOwnership_RevertInvalidOwner() public {
        vm.expectRevert("CrossBeg: invalid new owner");
        crossBeg.transferOwnership(address(0));
    }

    function test_TransferOwnership_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: not owner");
        crossBeg.transferOwnership(user2);
    }

    function test_SetRemoteContract() public {
        crossBeg.setRemoteContract(3, user1);
        assertEq(crossBeg.remoteCrossBegContracts(3), user1);
    }

    function test_SetRemoteContracts() public {
        uint32[] memory chainIds = new uint32[](2);
        address[] memory contracts = new address[](2);
        
        chainIds[0] = 3;
        chainIds[1] = 4;
        contracts[0] = user1;
        contracts[1] = user2;
        
        crossBeg.setRemoteContracts(chainIds, contracts);
        
        assertEq(crossBeg.remoteCrossBegContracts(3), user1);
        assertEq(crossBeg.remoteCrossBegContracts(4), user2);
    }

    function test_SetRemoteContracts_RevertLengthMismatch() public {
        uint32[] memory chainIds = new uint32[](2);
        address[] memory contracts = new address[](1);
        
        chainIds[0] = 3;
        chainIds[1] = 4;
        contracts[0] = user1;
        
        vm.expectRevert("CrossBeg: length mismatch");
        crossBeg.setRemoteContracts(chainIds, contracts);
    }

    function test_CreateLocalPaymentRequest() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit PaymentRequestCreated(
            1,
            user1,
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            block.timestamp
        );
        
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        assertEq(requestId, 1);
        assertEq(crossBeg.nextRequestId(), 2);
        
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(1);
        assertEq(request.id, 1);
        assertEq(request.requester, user1);
        assertEq(request.target, user2);
        assertEq(request.amount, 1 ether);
        assertEq(request.token, "ETH");
        assertEq(request.originChain, LOCAL_DOMAIN);
        assertEq(request.targetChain, LOCAL_DOMAIN);
        assertEq(request.message, "Test request");
        assertEq(uint256(request.status), uint256(CrossBegPaymentRequest.RequestStatus.Pending));
        assertEq(request.timestamp, block.timestamp);
        assertEq(request.expiryTime, block.timestamp + crossBeg.DEFAULT_EXPIRY_TIME());
        
        // Check user mappings
        uint256[] memory sentRequests = crossBeg.getUserSentRequests(user1);
        assertEq(sentRequests.length, 1);
        assertEq(sentRequests[0], 1);
        
        uint256[] memory receivedRequests = crossBeg.getUserReceivedRequests(user2);
        assertEq(receivedRequests.length, 1);
        assertEq(receivedRequests[0], 1);
    }

    function test_CreateCrossChainPaymentRequest() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit PaymentRequestCreated(
            1,
            user1,
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Cross-chain request",
            block.timestamp
        );
        
        uint256 requestId = crossBeg.createPaymentRequest{value: 0.001 ether}(
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Cross-chain request",
            0
        );
        
        assertEq(requestId, 1);
        
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(1);
        assertEq(request.targetChain, REMOTE_DOMAIN);
        
        // Check that cross-chain message was sent
        uint256[] memory sentRequests = crossBeg.getUserSentRequests(user1);
        assertEq(sentRequests.length, 1);
        
        // Target should not have received request locally (it's cross-chain)
        uint256[] memory receivedRequests = crossBeg.getUserReceivedRequests(user2);
        assertEq(receivedRequests.length, 0);
    }

    function test_CreatePaymentRequest_RevertInvalidTarget() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: invalid target address");
        crossBeg.createPaymentRequest(
            address(0),
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test",
            0
        );
    }

    function test_CreatePaymentRequest_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: amount must be greater than zero");
        crossBeg.createPaymentRequest(
            user2,
            0,
            "ETH",
            LOCAL_DOMAIN,
            "Test",
            0
        );
    }

    function test_CreatePaymentRequest_RevertSelfRequest() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: cannot request from yourself");
        crossBeg.createPaymentRequest(
            user1,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test",
            0
        );
    }

    function test_CreatePaymentRequest_RevertEmptyToken() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: token cannot be empty");
        crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "",
            LOCAL_DOMAIN,
            "Test",
            0
        );
    }

    function test_CreatePaymentRequest_RevertInvalidExpiryTime() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: invalid expiry time");
        crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test",
            30 minutes // Less than MIN_EXPIRY_TIME
        );
    }

    function test_CreatePaymentRequest_RevertUnsupportedChain() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: chain not supported");
        crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            999, // Unsupported chain
            "Test",
            0
        );
    }

    function test_CreatePaymentRequest_RevertInsufficientGasPayment() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: insufficient gas payment");
        crossBeg.createPaymentRequest{value: 0.0001 ether}( // Too little gas
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Test",
            0
        );
    }

    function test_HandleCrossChainMessage() public {
        // Create a cross-chain message
        uint256 requestId = 1;
        address requester = user1;
        address target = user2;
        uint256 amount = 1 ether;
        string memory token = "ETH";
        uint32 originChain = REMOTE_DOMAIN;
        string memory message = "Cross-chain request";
        uint256 timestamp = block.timestamp;
        uint256 expiryTime = block.timestamp + 7 days;
        
        bytes memory messageBody = abi.encode(
            requestId,
            requester,
            target,
            amount,
            token,
            originChain,
            message,
            timestamp,
            expiryTime
        );
        
        vm.expectEmit(true, true, true, true);
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
        
        // Simulate message delivery from remote contract
        bytes32 sender = bytes32(uint256(uint160(address(crossBeg))));
        mockMailbox.deliverMessage(address(crossBeg), REMOTE_DOMAIN, sender, messageBody);
        
        // Check that request was stored
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(requestId);
        assertEq(request.id, requestId);
        assertEq(request.requester, requester);
        assertEq(request.target, target);
        assertEq(request.amount, amount);
        assertEq(request.token, token);
        assertEq(request.originChain, originChain);
        assertEq(request.targetChain, LOCAL_DOMAIN);
        
        // Check that target received the request
        uint256[] memory receivedRequests = crossBeg.getUserReceivedRequests(target);
        assertEq(receivedRequests.length, 1);
        assertEq(receivedRequests[0], requestId);
    }

    function test_HandleCrossChainMessage_RevertInvalidSender() public {
        bytes memory messageBody = abi.encode(
            1,
            user1,
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Test",
            block.timestamp,
            block.timestamp + 7 days
        );
        
        // Use invalid sender
        bytes32 invalidSender = bytes32(uint256(uint160(user3)));
        
        vm.expectRevert("CrossBeg: invalid sender");
        mockMailbox.deliverMessage(address(crossBeg), REMOTE_DOMAIN, invalidSender, messageBody);
    }

    function test_HandleCrossChainMessage_RevertExpiredRequest() public {
        // Create expired message with proper timestamps
        // Set current time to a known value
        vm.warp(1000000);
        
        bytes memory messageBody = abi.encode(
            1,
            user1,
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Test",
            999000,  // Some timestamp in the past
            999999   // Expired timestamp in the past (before current time)
        );
        
        bytes32 sender = bytes32(uint256(uint160(address(crossBeg))));
        
        vm.expectRevert("CrossBeg: request expired");
        mockMailbox.deliverMessage(address(crossBeg), REMOTE_DOMAIN, sender, messageBody);
    }

    function test_FulfillPaymentRequest() public {
        // Create a local request
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        // Fulfill the request
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit PaymentRequestFulfilled(
            requestId,
            user2,
            1 ether,
            "ETH",
            "0x123abc"
        );
        
        crossBeg.fulfillPaymentRequest(requestId, "0x123abc");
        
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(requestId);
        assertEq(uint256(request.status), uint256(CrossBegPaymentRequest.RequestStatus.Fulfilled));
        assertEq(request.fulfillmentTxHash, "0x123abc");
    }

    function test_FulfillPaymentRequest_RevertNotTarget() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        vm.prank(user3);
        vm.expectRevert("CrossBeg: not the target of this request");
        crossBeg.fulfillPaymentRequest(requestId, "0x123abc");
    }

    function test_FulfillPaymentRequest_RevertRequestNotPending() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        // Fulfill first time
        vm.prank(user2);
        crossBeg.fulfillPaymentRequest(requestId, "0x123abc");
        
        // Try to fulfill again
        vm.prank(user2);
        vm.expectRevert("CrossBeg: request not pending");
        crossBeg.fulfillPaymentRequest(requestId, "0x456def");
    }

    function test_FulfillPaymentRequest_RevertExpiredRequest() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            crossBeg.MIN_EXPIRY_TIME()
        );
        
        // Fast forward past expiry
        vm.warp(block.timestamp + crossBeg.MIN_EXPIRY_TIME() + 1);
        
        vm.prank(user2);
        vm.expectRevert("CrossBeg: request expired");
        crossBeg.fulfillPaymentRequest(requestId, "0x123abc");
    }

    function test_FulfillPaymentRequest_RevertEmptyTxHash() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        vm.prank(user2);
        vm.expectRevert("CrossBeg: transaction hash required");
        crossBeg.fulfillPaymentRequest(requestId, "");
    }

    function test_CancelPaymentRequest() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit PaymentRequestCancelled(requestId, user1);
        
        crossBeg.cancelPaymentRequest(requestId);
        
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(requestId);
        assertEq(uint256(request.status), uint256(CrossBegPaymentRequest.RequestStatus.Cancelled));
    }

    function test_CancelPaymentRequest_RevertNotRequester() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        vm.prank(user2);
        vm.expectRevert("CrossBeg: not the requester");
        crossBeg.cancelPaymentRequest(requestId);
    }

    function test_CancelPaymentRequest_RevertNotPending() public {
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            0
        );
        
        // Cancel first time
        vm.prank(user1);
        crossBeg.cancelPaymentRequest(requestId);
        
        // Try to cancel again
        vm.prank(user1);
        vm.expectRevert("CrossBeg: request not pending");
        crossBeg.cancelPaymentRequest(requestId);
    }

    function test_MarkExpiredRequests() public {
        // Create requests with different expiry times
        vm.prank(user1);
        uint256 requestId1 = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request 1",
            crossBeg.MIN_EXPIRY_TIME()
        );
        
        vm.prank(user1);
        uint256 requestId2 = crossBeg.createPaymentRequest(
            user2,
            2 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request 2",
            crossBeg.DEFAULT_EXPIRY_TIME()
        );
        
        // Fast forward past first request expiry
        vm.warp(block.timestamp + crossBeg.MIN_EXPIRY_TIME() + 1);
        
        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        
        crossBeg.markExpiredRequests(requestIds);
        
        // Check statuses
        CrossBegPaymentRequest.PaymentRequest memory request1 = crossBeg.getPaymentRequest(requestId1);
        CrossBegPaymentRequest.PaymentRequest memory request2 = crossBeg.getPaymentRequest(requestId2);
        
        assertEq(uint256(request1.status), uint256(CrossBegPaymentRequest.RequestStatus.Expired));
        assertEq(uint256(request2.status), uint256(CrossBegPaymentRequest.RequestStatus.Pending));
    }

    function test_GetPaymentRequests() public {
        // Create multiple requests
        vm.prank(user1);
        uint256 requestId1 = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request 1",
            0
        );
        
        vm.prank(user1);
        uint256 requestId2 = crossBeg.createPaymentRequest(
            user2,
            2 ether,
            "USDC",
            LOCAL_DOMAIN,
            "Test request 2",
            0
        );
        
        uint256[] memory requestIds = new uint256[](2);
        requestIds[0] = requestId1;
        requestIds[1] = requestId2;
        
        CrossBegPaymentRequest.PaymentRequest[] memory requests = crossBeg.getPaymentRequests(requestIds);
        
        assertEq(requests.length, 2);
        assertEq(requests[0].id, requestId1);
        assertEq(requests[0].amount, 1 ether);
        assertEq(requests[0].token, "ETH");
        assertEq(requests[1].id, requestId2);
        assertEq(requests[1].amount, 2 ether);
        assertEq(requests[1].token, "USDC");
    }

    function test_QuoteGasPayment() public view {
        bytes memory messageBody = abi.encode(
            1,
            user1,
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test",
            block.timestamp,
            block.timestamp + 7 days
        );
        
        uint256 gasPayment = crossBeg.quoteGasPayment(REMOTE_DOMAIN, messageBody);
        assertEq(gasPayment, 0.001 ether);
    }

    function test_QuoteGasPayment_RevertUnsupportedChain() public {
        bytes memory messageBody = "test";
        
        vm.expectRevert("CrossBeg: chain not supported");
        crossBeg.quoteGasPayment(999, messageBody);
    }

    function test_GetSupportedChains() public view {
        uint32[] memory chainIds = new uint32[](3);
        chainIds[0] = LOCAL_DOMAIN;
        chainIds[1] = REMOTE_DOMAIN;
        chainIds[2] = 999;
        
        bool[] memory supported = crossBeg.getSupportedChains(chainIds);
        
        assertEq(supported.length, 3);
        assertEq(supported[0], false); // Local domain not in remote contracts
        assertEq(supported[1], true);  // Remote domain is set
        assertEq(supported[2], false); // Chain 999 not supported
    }

    function test_EmergencyWithdraw() public {
        // Send some ETH to the contract
        vm.deal(address(crossBeg), 1 ether);
        
        uint256 ownerBalanceBefore = owner.balance;
        crossBeg.emergencyWithdraw();
        uint256 ownerBalanceAfter = owner.balance;
        
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 1 ether);
        assertEq(address(crossBeg).balance, 0);
    }

    function test_EmergencyWithdraw_RevertNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("CrossBeg: not owner");
        crossBeg.emergencyWithdraw();
    }

    function test_GetContractStats() public {
        // Create some requests
        vm.prank(user1);
        crossBeg.createPaymentRequest(user2, 1 ether, "ETH", LOCAL_DOMAIN, "Test 1", 0);
        
        vm.prank(user1);
        crossBeg.createPaymentRequest(user2, 2 ether, "ETH", LOCAL_DOMAIN, "Test 2", 0);
        
        (uint256 totalRequests, uint256 currentRequestId) = crossBeg.getContractStats();
        
        assertEq(totalRequests, 2);
        assertEq(currentRequestId, 3);
    }

    function test_ReceiveEther() public {
        // Test that contract can receive ETH
        vm.deal(user1, 1 ether);
        
        vm.prank(user1);
        (bool success,) = address(crossBeg).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(crossBeg).balance, 1 ether);
    }

    function test_RequestNonexistent() public {
        vm.expectRevert("CrossBeg: request does not exist");
        crossBeg.getPaymentRequest(999);
    }

    function test_CustomExpiryTime() public {
        uint256 customExpiry = 3 days;
        
        vm.prank(user1);
        uint256 requestId = crossBeg.createPaymentRequest(
            user2,
            1 ether,
            "ETH",
            LOCAL_DOMAIN,
            "Test request",
            customExpiry
        );
        
        CrossBegPaymentRequest.PaymentRequest memory request = crossBeg.getPaymentRequest(requestId);
        assertEq(request.expiryTime, block.timestamp + customExpiry);
    }

    function test_GasRefund() public {
        uint256 excessGas = 0.005 ether;
        uint256 user1BalanceBefore = user1.balance;
        
        vm.prank(user1);
        crossBeg.createPaymentRequest{value: excessGas}(
            user2,
            1 ether,
            "ETH",
            REMOTE_DOMAIN,
            "Test request",
            0
        );
        
        uint256 user1BalanceAfter = user1.balance;
        uint256 actualGasCost = 0.001 ether; // Mock mailbox quote
        
        // User should have been refunded the excess
        assertEq(user1BalanceBefore - user1BalanceAfter, actualGasCost);
    }

    // Allow test contract to receive ETH refunds
    receive() external payable {}
}