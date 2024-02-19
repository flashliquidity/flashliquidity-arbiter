// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniswapV3Adapter} from "../../../contracts/adapters/UniswapV3Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";

contract UniswapV3AdapterTest is Test {
    UniswapV3Adapter public adapter;
    address public governor = makeAddr("governor");
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");
    address public rob = makeAddr("rob");
    address public factory0 = makeAddr("factory0");
    address public factory1 = makeAddr("factory1");
    address public quoter0 = makeAddr("quoter0");
    address public quoter1 = makeAddr("quoter1");

    function setUp() public {
        adapter = new UniswapV3Adapter(governor, "UniswapV3Adapter 1.0");
    }

    function test__UniswapV3Adapter_addFactory() public {
        uint24[] memory feeValues = new uint24[](2);
        feeValues[0] = 500;
        feeValues[1] = 3000;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addFactory(factory0, quoter0, feeValues);
        vm.prank(governor);
        adapter.addFactory(factory0, quoter0, feeValues);
        (address factory, address quoter, uint24[] memory fees) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory0);
        assertTrue(fees[0] == feeValues[0] && fees[1] == feeValues[1]);
        assertTrue(quoter == quoter0);
    }

    function test__UniswapV3Adapter_removeFactory() public {
        uint24[] memory feeValues0 = new uint24[](2);
        uint24[] memory feeValues1 = new uint24[](2);
        feeValues0[0] = 500;
        feeValues0[1] = 3000;
        feeValues1[0] = 100;
        feeValues1[1] = 500;
        vm.startPrank(governor);
        adapter.addFactory(factory0, quoter0, feeValues0);
        adapter.addFactory(factory1, quoter1, feeValues1);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeFactory(0);
        vm.prank(governor);
        adapter.removeFactory(0);
        (address factory, address quoter, uint24[] memory fees) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory1);
        assertTrue(quoter == quoter1);
        assertTrue(fees[0] == feeValues1[0] && fees[1] == feeValues1[1]);
    }

    function test__UniswapV3Adapter_addFactoryFees() public {
        uint24[] memory feeValues = new uint24[](1);
        feeValues[0] = 500;
        vm.prank(governor);
        adapter.addFactory(factory0, quoter0, feeValues);
        uint24[] memory newFeeValues = new uint24[](2);
        newFeeValues[0] = 100;
        newFeeValues[1] = 3000;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addFactoryFees(factory0, newFeeValues);
        vm.prank(governor);
        adapter.addFactoryFees(factory0, newFeeValues);
        (address factory, address quoter, uint24[] memory fees) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory0);
        assertTrue(fees[0] == feeValues[0] && fees[1] == newFeeValues[0] && fees[2] == newFeeValues[1]);
        assertTrue(quoter == quoter0);
    }

    function test__UniswapV3Adapter_removeFactoryFees() public {
        uint24[] memory feeValues = new uint24[](2);
        feeValues[0] = 500;
        feeValues[1] = 3000;
        vm.prank(governor);
        adapter.addFactory(factory0, quoter0, feeValues);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeFactoryFee(factory0, 0);
        vm.prank(governor);
        adapter.removeFactoryFee(factory0, 0);
        (address factory, address quoter, uint24[] memory fees) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory0);
        assertTrue(fees[0] == feeValues[1]);
        assertTrue(quoter == quoter0);
    }
}
