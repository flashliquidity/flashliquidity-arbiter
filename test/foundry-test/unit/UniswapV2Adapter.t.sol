// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniswapV2Adapter} from "../../../contracts/adapters/UniswapV2Adapter.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";

contract UniswapV2AdapterTest is Test {
    UniswapV2Adapter adapter;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address rob = makeAddr("rob");
    address factory0 = makeAddr("factory0");
    address factory1 = makeAddr("factory1");

    function setUp() public {
        adapter = new UniswapV2Adapter(governor, "UniswapV2Adapter 1.0");
    }

    function test__UniswapV2Adapter_addFactory() public {
        uint48 feeNumeratorVal = 997;
        uint48 feeDenominatorVal = 1000;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.addFactory(factory0, feeNumeratorVal, feeDenominatorVal);
        vm.prank(governor);
        adapter.addFactory(factory0, feeNumeratorVal, feeDenominatorVal);
        (address factory, uint48 feeNumerator, uint48 feeDenominator) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory0);
        assertTrue(feeNumerator == feeNumeratorVal);
        assertTrue(feeDenominator == feeDenominatorVal);
    }

    function test__UniswapV2Adapter_removeFactory() public {
        uint48 feeNumeratorVal0 = 997;
        uint48 feeNumeratorVal1 = 998;
        uint48 feeDenominatorVal = 1000;
        vm.startPrank(governor);
        adapter.addFactory(factory0, feeNumeratorVal0, feeDenominatorVal);
        adapter.addFactory(factory1, feeNumeratorVal1, feeDenominatorVal);
        vm.stopPrank();
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        adapter.removeFactory(0);
        vm.prank(governor);
        adapter.removeFactory(0);
        (address factory, uint48 feeNumerator, uint48 feeDenominator) = adapter.getFactoryAtIndex(0);
        assertTrue(factory == factory1);
        assertTrue(feeNumerator == feeNumeratorVal1);
        assertTrue(feeDenominator == feeDenominatorVal);
    }
}
