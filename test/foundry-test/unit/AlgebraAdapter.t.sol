// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AlgebraAdapter} from "../../../contracts/adapters/AlgebraAdapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";

contract AlgebraAdapterTest is Test {
    AlgebraAdapter adapter;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address factory0 = makeAddr("factory0");
    address factory1 = makeAddr("factory1");
    address quoter0 = makeAddr("quoter0");
    address quoter1 = makeAddr("quoter1");

    function setUp() public {
        adapter = new AlgebraAdapter(governor, "AlgebraAdapter 1.0");
    }

    function test__AlgebraAdapter_addFactory() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addFactory(factory0, quoter0);
        vm.prank(governor);
        adapter.addFactory(factory0, quoter0);
        (address factory, address quoter) = adapter.getFactoryAtIndex(0);
        assertEq(factory, factory0);
        assertEq(quoter, quoter0);
    }

    function test__AlgebraAdapter_removeFactory() public {
        vm.startPrank(governor);
        adapter.addFactory(factory0, quoter0);
        adapter.addFactory(factory1, quoter1);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeFactory(0);
        vm.prank(governor);
        adapter.removeFactory(0);
        (address factory, address quoter) = adapter.getFactoryAtIndex(0);
        assertEq(factory, factory1);
        assertEq(quoter, quoter1);
    }
}
