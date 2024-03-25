// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TraderJoeLBAdapter} from "../../../contracts/adapters/TraderJoeLBAdapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";

contract TraderJoeLBAdapterTest is Test {
    TraderJoeLBAdapter adapter;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address rob = makeAddr("rob");
    address factory0 = makeAddr("factory0");
    address factory1 = makeAddr("factory1");

    function setUp() public {
        adapter = new TraderJoeLBAdapter(governor, "TraderJoeLBAdapter 1.0");
    }

    function test__TraderJoeLBAdapter_addFactory() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addFactory(factory0);
        vm.prank(governor);
        adapter.addFactory(factory0);
        assertEq(adapter.getFactoryAtIndex(0), factory0);
    }

    function test__TraderJoeLBAdapter_removeFactory() public {
        vm.startPrank(governor);
        adapter.addFactory(factory0);
        adapter.addFactory(factory1);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeFactory(0);
        vm.prank(governor);
        adapter.removeFactory(0);
        assertEq(adapter.getFactoryAtIndex(0), factory1);
    }
}
