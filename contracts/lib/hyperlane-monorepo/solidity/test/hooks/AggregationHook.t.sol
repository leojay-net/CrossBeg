// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {StaticAggregationHook} from "../../contracts/hooks/aggregation/StaticAggregationHook.sol";
import {StaticAggregationHookFactory} from "../../contracts/hooks/aggregation/StaticAggregationHookFactory.sol";
import {TestPostDispatchHook} from "../../contracts/test/TestPostDispatchHook.sol";
import {IPostDispatchHook} from "../../contracts/interfaces/hooks/IPostDispatchHook.sol";

contract AggregationHookTest is Test {
    StaticAggregationHookFactory internal factory;
    StaticAggregationHook internal hook;

    uint256 internal constant PER_HOOK_GAS_AMOUNT = 25000;

    function setUp() public {
        factory = new StaticAggregationHookFactory();
    }

    function deployHooks(uint8 n, uint256 fee)
        internal
        returns (address[] memory)
    {
        address[] memory hooks = new address[](n);
        for (uint8 i = 0; i < n; i++) {
            TestPostDispatchHook subHook = new TestPostDispatchHook();
            subHook.setFee(fee);
            hooks[i] = address(subHook);
        }
        hook = StaticAggregationHook(factory.deploy(hooks));
        return hooks;
    }

    function testPostDispatch(uint8 _hooks) public {
        uint256 fee = PER_HOOK_GAS_AMOUNT;
        address[] memory hooksDeployed = deployHooks(_hooks, fee);
        uint256 _msgValue = hooksDeployed.length * fee;

        bytes memory message = abi.encodePacked("hello world");
        for (uint256 i = 0; i < hooksDeployed.length; i++) {
            vm.expectCall(
                hooksDeployed[i],
                PER_HOOK_GAS_AMOUNT,
                abi.encodeCall(
                    TestPostDispatchHook(hooksDeployed[i]).postDispatch,
                    ("", "hello world")
                )
            );
        }
        hook.postDispatch{value: _msgValue}("", message);
    }

    function testPostDispatch_reverts_outOfFund(uint8 _hooks, uint8 k) public {
        uint256 fee = PER_HOOK_GAS_AMOUNT;
        address[] memory hooksDeployed = deployHooks(_hooks, fee);
        vm.assume(k < hooksDeployed.length);
        uint256 _msgValue = uint256(k) * fee;

        bytes memory message = abi.encodePacked("hello world");
        for (uint256 i = 0; i < k; i++) {
            vm.expectCall(
                hooksDeployed[i],
                fee,
                abi.encodeCall(
                    TestPostDispatchHook(hooksDeployed[i]).postDispatch,
                    ("", "hello world")
                )
            );
        }
        vm.expectRevert(); // outOfFund
        hook.postDispatch{value: _msgValue}("", message);
    }

    function testQuoteDispatch(uint8 _hooks) public {
        uint256 fee = PER_HOOK_GAS_AMOUNT;
        address[] memory hooksDeployed = deployHooks(_hooks, fee);
        uint256 _msgValue = hooksDeployed.length * fee;

        bytes memory message = abi.encodePacked("hello world");
        uint256 totalQuote = hook.quoteDispatch("", message);

        assertEq(totalQuote, _msgValue);
    }

    function testMetadata(uint8 _hooks) public {
        uint256 fee = PER_HOOK_GAS_AMOUNT;
        address[] memory expectedHooks = deployHooks(_hooks, fee);
        address[] memory actualHook = hook.hooks("");
        assertEq(actualHook, expectedHooks);
    }

    function testHookType() public {
        deployHooks(1, 0);
        assertEq(hook.hookType(), uint8(IPostDispatchHook.Types.AGGREGATION));
    }
}
